import Accelerate
import AVFoundation
import Combine
import os

private let log = Logger(subsystem: "VolumeMeter", category: "AcousticPace")

/// Estimates words-per-minute from acoustic features (syllable-rate detection)
/// using only the Accelerate framework — no speech recognition, no transcription.
/// Works on macOS 14+.
final class AcousticPaceAnalyzer: ObservableObject {
    @Published var wordsPerMinute: Double = 0
    @Published var wpmHistory: [Double] = []
    @Published var isAnalyzing: Bool = false

    static let maxHistoryCount = 90

    // MARK: - Tuning parameters

    private let hpCutoff: Float = 300       // Hz – highpass
    private let lpCutoff: Float = 3000      // Hz – lowpass
    private let envelopeLPF: Float = 10     // Hz – envelope smoother
    private let downsampleRate: Float = 100 // Hz – envelope sample rate
    private let analysisWindow: Float = 3   // seconds
    private let bufferDuration: Float = 5   // seconds of rolling envelope
    private let minPeakDistSamples = 8      // 80 ms at 100 Hz
    private let peakThresholdScale: Float = 0.3
    private let peakDipFactor: Float = 0.71 // −3 dB valley depth
    private let syllablesPerWord: Double = 1.5
    private let smoothingAlpha: Double = 0.3
    private let vadOnsetDB: Float = -38
    private let vadOffsetDB: Float = -42
    private let vadHoldTime: Float = 0.3    // seconds

    // MARK: - DSP state

    private var hpFilter: vDSP.Biquad<Float>?
    private var lpFilter: vDSP.Biquad<Float>?
    private var envFilter: vDSP.Biquad<Float>?
    private var configuredSampleRate: Double = 0

    /// Rolling envelope buffer at `downsampleRate` Hz
    private var envelopeBuffer: [Float] = []
    private var maxEnvelopeSamples: Int = 0

    // MARK: - VAD state

    private var isSpeaking = false
    private var vadHoldRemaining: Float = 0

    // MARK: - Smoothing / history

    private var smoothedWPM: Double = 0
    private var timerCancellable: AnyCancellable?

    // MARK: - Public API

    func startAnalyzing() {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        smoothedWPM = 0
        wordsPerMinute = 0
        wpmHistory.removeAll()
        envelopeBuffer.removeAll()
        isSpeaking = false
        vadHoldRemaining = 0

        // Sample history at ~3 Hz
        timerCancellable = Timer.publish(every: 1.0 / 3.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.appendToHistory()
            }
    }

    func stopAnalyzing() {
        timerCancellable?.cancel()
        timerCancellable = nil
        isAnalyzing = false
        smoothedWPM = 0
        wordsPerMinute = 0
        wpmHistory.removeAll()
        envelopeBuffer.removeAll()

        // Reset filters so they reinitialise on next start
        hpFilter = nil
        lpFilter = nil
        envFilter = nil
        configuredSampleRate = 0
    }

    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isAnalyzing else { return }
        let sampleRate = Float(buffer.format.sampleRate)
        guard sampleRate > 0 else { return }

        // Lazy-init filters on first buffer (or if sample rate changes)
        if configuredSampleRate != Double(sampleRate) {
            configureFilters(sampleRate: sampleRate)
        }

        // 1. Mono mixdown
        let mono = monoMix(buffer)
        guard !mono.isEmpty else { return }

        // 2. Bandpass: HP 300 Hz → LP 3000 Hz
        guard var hpFilter, var lpFilter, var envFilter else { return }
        let hpOut = hpFilter.apply(input: mono)
        let bpOut = lpFilter.apply(input: hpOut)
        self.hpFilter = hpFilter
        self.lpFilter = lpFilter

        // 3. Full-wave rectify
        let rectified = vDSP.absolute(bpOut)

        // 4. Envelope: lowpass 10 Hz
        let envRaw = envFilter.apply(input: rectified)
        self.envFilter = envFilter

        // 5. Downsample to 100 Hz
        let step = max(1, Int(sampleRate / downsampleRate))
        var downsampled: [Float] = []
        downsampled.reserveCapacity(envRaw.count / step + 1)
        var i = 0
        while i < envRaw.count {
            downsampled.append(envRaw[i])
            i += step
        }

        // 6. Append to rolling buffer
        envelopeBuffer.append(contentsOf: downsampled)
        if envelopeBuffer.count > maxEnvelopeSamples {
            envelopeBuffer.removeFirst(envelopeBuffer.count - maxEnvelopeSamples)
        }

        // 7. VAD check on this chunk
        let bufferSeconds = Float(mono.count) / sampleRate
        updateVAD(mono: mono, sampleRate: sampleRate, chunkDuration: bufferSeconds)

        // 8. Peak detection on latest `analysisWindow` seconds of envelope
        let analysisSamples = Int(analysisWindow * downsampleRate)
        let window: ArraySlice<Float>
        if envelopeBuffer.count > analysisSamples {
            window = envelopeBuffer.suffix(analysisSamples)
        } else {
            window = envelopeBuffer[...]
        }

        let syllableCount: Int
        if isSpeaking {
            syllableCount = countPeaks(in: Array(window))
        } else {
            syllableCount = 0
        }

        // 9. Syllables → WPM
        let windowSeconds = Double(window.count) / Double(downsampleRate)
        let rawWPM: Double
        if syllableCount > 0, windowSeconds >= 0.5 {
            rawWPM = (Double(syllableCount) / syllablesPerWord) / windowSeconds * 60.0
        } else {
            rawWPM = 0
        }

        // 10. Smooth (published value updated on timer tick, not every buffer)
        smoothedWPM = smoothingAlpha * rawWPM + (1 - smoothingAlpha) * smoothedWPM
        if smoothedWPM < 5 { smoothedWPM = 0 }
    }

    // MARK: - Filter configuration

    private func configureFilters(sampleRate: Float) {
        configuredSampleRate = Double(sampleRate)
        maxEnvelopeSamples = Int(bufferDuration * downsampleRate)
        envelopeBuffer.removeAll()
        envelopeBuffer.reserveCapacity(maxEnvelopeSamples)

        hpFilter = makeHighpass(cutoff: hpCutoff, sampleRate: sampleRate)
        lpFilter = makeLowpass(cutoff: lpCutoff, sampleRate: sampleRate)
        envFilter = makeLowpass(cutoff: envelopeLPF, sampleRate: sampleRate)

        log.info("Filters configured for sample rate \(sampleRate, privacy: .public) Hz")
    }

    // MARK: - Biquad coefficient helpers (Audio EQ Cookbook)

    private func makeLowpass(cutoff: Float, sampleRate: Float) -> vDSP.Biquad<Float> {
        let w0 = 2 * Float.pi * cutoff / sampleRate
        let alpha = sin(w0) / (2 * 0.7071) // Q = 0.7071 (Butterworth)
        let cosw0 = cos(w0)

        let b0 = (1 - cosw0) / 2
        let b1 = 1 - cosw0
        let b2 = (1 - cosw0) / 2
        let a0 = 1 + alpha
        let a1 = -2 * cosw0
        let a2 = 1 - alpha

        return vDSP.Biquad(
            coefficients: [Double(b0/a0), Double(b1/a0), Double(b2/a0), Double(a1/a0), Double(a2/a0)],
            channelCount: 1,
            sectionCount: 1,
            ofType: Float.self
        )!
    }

    private func makeHighpass(cutoff: Float, sampleRate: Float) -> vDSP.Biquad<Float> {
        let w0 = 2 * Float.pi * cutoff / sampleRate
        let alpha = sin(w0) / (2 * 0.7071)
        let cosw0 = cos(w0)

        let b0 = (1 + cosw0) / 2
        let b1 = -(1 + cosw0)
        let b2 = (1 + cosw0) / 2
        let a0 = 1 + alpha
        let a1 = -2 * cosw0
        let a2 = 1 - alpha

        return vDSP.Biquad(
            coefficients: [Double(b0/a0), Double(b1/a0), Double(b2/a0), Double(a1/a0), Double(a2/a0)],
            channelCount: 1,
            sectionCount: 1,
            ofType: Float.self
        )!
    }

    // MARK: - Mono mixdown

    private func monoMix(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return [] }
        let channelCount = Int(buffer.format.channelCount)

        if channelCount == 1 {
            return Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        }

        // Average all channels
        var mono = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        for ch in 1..<channelCount {
            let chPtr = UnsafeBufferPointer(start: channelData[ch], count: frameCount)
            vDSP.add(mono, Array(chPtr), result: &mono)
        }
        let scale = 1.0 / Float(channelCount)
        vDSP.multiply(scale, mono, result: &mono)
        return mono
    }

    // MARK: - VAD (voice activity detection)

    private func updateVAD(mono: [Float], sampleRate: Float, chunkDuration: Float) {
        // RMS → dBFS
        var rms: Float = 0
        vDSP_measqv(mono, 1, &rms, vDSP_Length(mono.count))
        rms = sqrt(rms)
        let dbFS = rms > 0 ? 20 * log10(rms) : -100

        if dbFS >= vadOnsetDB {
            isSpeaking = true
            vadHoldRemaining = vadHoldTime
        } else if dbFS < vadOffsetDB {
            vadHoldRemaining -= chunkDuration
            if vadHoldRemaining <= 0 {
                isSpeaking = false
                vadHoldRemaining = 0
            }
        } else {
            // Between offset and onset — maintain current state, decrement hold
            if isSpeaking {
                vadHoldRemaining -= chunkDuration
                if vadHoldRemaining <= 0 {
                    isSpeaking = false
                    vadHoldRemaining = 0
                }
            }
        }
    }

    // MARK: - Peak detection

    private func countPeaks(in envelope: [Float]) -> Int {
        guard envelope.count >= 3 else { return 0 }

        // Adaptive threshold: mean + 0.3 * stddev
        var mean: Float = 0
        var stddev: Float = 0
        vDSP_normalize(envelope, 1, nil, 1, &mean, &stddev, vDSP_Length(envelope.count))
        let threshold = mean + peakThresholdScale * stddev

        var peaks: [Int] = []

        for i in 1..<(envelope.count - 1) {
            let val = envelope[i]
            guard val > threshold else { continue }
            guard val > envelope[i - 1], val > envelope[i + 1] else { continue }

            // Enforce minimum distance
            if let lastPeak = peaks.last, (i - lastPeak) < minPeakDistSamples {
                // Keep the larger peak
                if val > envelope[lastPeak] {
                    peaks[peaks.count - 1] = i
                }
                continue
            }

            // Require valley depth: check that there's a dip of at least peakDipFactor
            // between this peak and the previous one
            if let lastPeak = peaks.last {
                let minBetween = envelope[lastPeak...i].min() ?? val
                let prevPeakVal = envelope[lastPeak]
                let dipRequired = min(prevPeakVal, val) * peakDipFactor
                if minBetween > dipRequired {
                    // Not enough valley — keep larger peak
                    if val > prevPeakVal {
                        peaks[peaks.count - 1] = i
                    }
                    continue
                }
            }

            peaks.append(i)
        }

        return peaks.count
    }

    // MARK: - History

    private func appendToHistory() {
        wordsPerMinute = smoothedWPM
        wpmHistory.append(wordsPerMinute)
        if wpmHistory.count > Self.maxHistoryCount {
            wpmHistory.removeFirst(wpmHistory.count - Self.maxHistoryCount)
        }
    }
}
