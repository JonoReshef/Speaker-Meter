import AVFoundation
import Combine

final class AudioManager: ObservableObject {
    @Published var level: Float = 0.0
    @Published var decibelLevel: Float = -60.0
    @Published var isMonitoring: Bool = false
    @Published var errorMessage: String?

    private var audioEngine: AVAudioEngine?
    private let smoothingFactor: Float = 0.3

    func startMonitoring() {
        guard !isMonitoring else { return }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            setupAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupAndStart()
                    } else {
                        self?.errorMessage = "Microphone access denied."
                    }
                }
            }
        case .denied, .restricted:
            errorMessage = "Microphone access denied. Open System Settings → Privacy & Security → Microphone to grant access."
        @unknown default:
            errorMessage = "Unknown microphone authorization status."
        }
    }

    func stopMonitoring() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        DispatchQueue.main.async {
            self.isMonitoring = false
            self.level = 0.0
            self.decibelLevel = -60.0
        }
    }

    private func setupAndStart() {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        do {
            try engine.start()
            audioEngine = engine
            isMonitoring = true
            errorMessage = nil
        } catch {
            errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
        }
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        var sumOfSquares: Float = 0.0
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for frame in 0..<frameLength {
                let sample = samples[frame]
                sumOfSquares += sample * sample
            }
        }

        let totalSamples = Float(frameLength * channelCount)
        let rms = sqrtf(sumOfSquares / totalSamples)

        let db: Float = rms > 0 ? 20.0 * log10f(rms) : -60.0
        let clampedDb = max(-60.0, min(0.0, db))

        // Normalize: -60dB → 0.0, 0dB → 1.0
        let normalized = (clampedDb + 60.0) / 60.0

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.level = self.level + self.smoothingFactor * (normalized - self.level)
            self.decibelLevel = clampedDb
        }
    }
}
