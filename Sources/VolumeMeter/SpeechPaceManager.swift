import AVFoundation
import Combine
import CoreMedia
import os
import Speech

private let log = Logger(subsystem: "VolumeMeter", category: "SpeechPace")

// MARK: - SpeechPaceManager (macOS 26+)

@available(macOS 26, *)
final class SpeechPaceManager: ObservableObject {
    @Published var wordsPerMinute: Double = 0
    @Published var wpmHistory: [Double] = []
    @Published var isAnalyzing: Bool = false
    @Published var speechError: String?

    static let maxHistoryCount = 90

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultTask: Task<Void, Never>?
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?

    private let windowDuration: TimeInterval = 3
    private var finalWordTimestamps: [TimeInterval] = []
    private var volatileWordTimestamps: [TimeInterval] = []
    private var sessionStartTime: Date?
    private var timerCancellable: AnyCancellable?
    private var smoothedWPM: Double = 0
    private let smoothingAlpha: Double = 1.0

    func startAnalyzing() {
        guard !isAnalyzing else { return }

        resultTask = Task { @MainActor in
            do {
                try await beginSession()
            } catch {
                self.speechError = error.localizedDescription
                self.isAnalyzing = false
            }
        }
    }

    func stopAnalyzing() {
        timerCancellable?.cancel()
        timerCancellable = nil
        inputContinuation?.finish()
        inputContinuation = nil
        resultTask?.cancel()
        resultTask = nil
        analyzer = nil
        transcriber = nil
        converter = nil
        analyzerFormat = nil
        finalWordTimestamps.removeAll()
        volatileWordTimestamps.removeAll()
        sessionStartTime = nil
        smoothedWPM = 0
        DispatchQueue.main.async {
            self.isAnalyzing = false
            self.wordsPerMinute = 0
            self.wpmHistory.removeAll()
        }
    }

    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let continuation = inputContinuation, let analyzerFormat else { return }

        do {
            let converted = try convertBuffer(buffer, to: analyzerFormat)
            continuation.yield(AnalyzerInput(buffer: converted))
        } catch {
            // Silently skip buffers that fail conversion
        }
    }

    // MARK: - Private

    private func beginSession() async throws {
        let newTranscriber = SpeechTranscriber(
            locale: Locale.current,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        transcriber = newTranscriber

        let newAnalyzer = SpeechAnalyzer(modules: [newTranscriber])
        analyzer = newAnalyzer

        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [newTranscriber]
        )

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = continuation
        sessionStartTime = Date()

        await MainActor.run {
            self.isAnalyzing = true
            self.speechError = nil
            self.startRecalculationTimer()
        }

        // Start consuming results in background
        let resultsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in newTranscriber.results {
                    await self.handleResult(result)
                }
            } catch is CancellationError {
                // Expected on stop
            } catch {
                await MainActor.run {
                    self.speechError = error.localizedDescription
                }
            }
        }

        do {
            try await newAnalyzer.start(inputSequence: stream)
        } catch {
            resultsTask.cancel()
            throw error
        }
    }

    @MainActor
    private func handleResult(_ result: SpeechTranscriber.Result) {
        let now = Date()
        let elapsed = now.timeIntervalSince(sessionStartTime ?? now)

        // Collect words and their raw audio start times
        var audioStarts: [TimeInterval?] = []
        for run in result.text.runs {
            let word = String(result.text.characters[run.range])
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            audioStarts.append(run.audioTimeRange?.start.seconds)
        }

        guard !audioStarts.isEmpty else { return }

        // Anchor the latest audio time to `elapsed` (wall-clock now),
        // then place earlier words relative to that anchor.
        // This avoids drift between audio-stream time and wall-clock time.
        let maxAudioTime = audioStarts.compactMap({ $0 }).max()
        var timestamps: [TimeInterval] = []
        for audioStart in audioStarts {
            if let audioT = audioStart, let maxT = maxAudioTime {
                timestamps.append(elapsed - (maxT - audioT))
            } else {
                timestamps.append(elapsed)
            }
        }

        let kind = result.isFinal ? "FINAL" : "VOLATILE"
        log.info("[SpeechPace] \(kind, privacy: .public) at elapsed=\(String(format: "%.1f", elapsed), privacy: .public)s: \(timestamps.count, privacy: .public) words, timestamps=\(timestamps.map { String(format: "%.1f", $0) }.joined(separator: ","), privacy: .public)")

        if result.isFinal {
            finalWordTimestamps.append(contentsOf: timestamps)
            volatileWordTimestamps.removeAll()
        } else {
            volatileWordTimestamps = timestamps
        }
    }

    private func startRecalculationTimer() {
        timerCancellable = Timer.publish(every: 1.0 / 3.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.timerRecalculateWPM()
            }
    }

    private func timerRecalculateWPM() {
        let now = Date()
        let elapsed = now.timeIntervalSince(sessionStartTime ?? now)
        let cutoff = elapsed - windowDuration
        let beforePrune = finalWordTimestamps.count
        finalWordTimestamps.removeAll { $0 < cutoff }
        let pruned = beforePrune - finalWordTimestamps.count

        let wordCount = finalWordTimestamps.count + volatileWordTimestamps.count

        if pruned > 0 {
            log.info("[SpeechPace] TIMER t=\(String(format: "%.1f", elapsed), privacy: .public): pruned \(pruned, privacy: .public) words (cutoff=\(String(format: "%.1f", cutoff), privacy: .public))")
        }

        var rawWPM: Double = 0
        if wordCount > 0 {
            let windowSpan = min(elapsed, windowDuration)
            if windowSpan >= 1 {
                rawWPM = (Double(wordCount) / windowSpan) * 60.0
            }
        }

        smoothedWPM = smoothingAlpha * rawWPM + (1 - smoothingAlpha) * smoothedWPM
        // Snap to zero when negligible
        if smoothedWPM < 5 { smoothedWPM = 0 }

        wordsPerMinute = smoothedWPM
        log.info("[SpeechPace] TIMER t=\(String(format: "%.1f", elapsed), privacy: .public): final=\(self.finalWordTimestamps.count, privacy: .public) volatile=\(self.volatileWordTimestamps.count, privacy: .public) raw=\(String(format: "%.0f", rawWPM), privacy: .public) → \(String(format: "%.0f", self.wordsPerMinute), privacy: .public) WPM")
        appendToHistory(wordsPerMinute)
    }

    private func appendToHistory(_ value: Double) {
        wpmHistory.append(value)
        if wpmHistory.count > Self.maxHistoryCount {
            wpmHistory.removeFirst(wpmHistory.count - Self.maxHistoryCount)
        }
    }

    private func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard buffer.format != format else { return buffer }

        if converter == nil || converter?.outputFormat != format || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
            converter?.primeMethod = .none
        }
        guard let converter else {
            throw NSError(domain: "SpeechPaceManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio converter"])
        }

        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else {
            throw NSError(domain: "SpeechPaceManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create output buffer"])
        }

        var done = false
        let status = converter.convert(to: output, error: nil) { _, statusPtr in
            defer { done = true }
            statusPtr.pointee = done ? .noDataNow : .haveData
            return done ? nil : buffer
        }
        guard status != .error else {
            throw NSError(domain: "SpeechPaceManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Audio conversion failed"])
        }
        return output
    }
}

// MARK: - SpeechPaceObserver (all macOS versions)

final class SpeechPaceObserver: ObservableObject {
    @Published var wordsPerMinute: Double = 0
    @Published var wpmHistory: [Double] = []
    @Published var isAnalyzing: Bool = false
    @Published var speechError: String?

    let isAvailable: Bool

    private var manager: AnyObject?
    private var cancellables = Set<AnyCancellable>()

    init() {
        if #available(macOS 26, *) {
            isAvailable = true
            let mgr = SpeechPaceManager()
            manager = mgr
            mgr.$wordsPerMinute
                .receive(on: RunLoop.main)
                .assign(to: &$wordsPerMinute)
            mgr.$wpmHistory
                .receive(on: RunLoop.main)
                .assign(to: &$wpmHistory)
            mgr.$isAnalyzing
                .receive(on: RunLoop.main)
                .assign(to: &$isAnalyzing)
            mgr.$speechError
                .receive(on: RunLoop.main)
                .assign(to: &$speechError)
        } else {
            isAvailable = false
        }
    }

    func startAnalyzing() {
        if #available(macOS 26, *) {
            (manager as? SpeechPaceManager)?.startAnalyzing()
        }
    }

    func stopAnalyzing() {
        if #available(macOS 26, *) {
            (manager as? SpeechPaceManager)?.stopAnalyzing()
        }
    }

    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        if #available(macOS 26, *) {
            (manager as? SpeechPaceManager)?.processAudioBuffer(buffer)
        }
    }
}
