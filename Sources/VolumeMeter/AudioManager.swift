import AVFoundation
import Combine
import CoreAudio

final class AudioManager: ObservableObject {
    @Published var level: Float = 0.0
    @Published var decibelLevel: Float = 0.0
    @Published var isMonitoring: Bool = false
    @Published var errorMessage: String?
    @Published var deviceName: String = "Unknown"

    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?

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
            self.decibelLevel = 0.0
        }
    }

    private func setupAndStart() {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
            self?.onAudioBuffer?(buffer)
        }

        do {
            try engine.start()
            audioEngine = engine
            isMonitoring = true
            errorMessage = nil
            deviceName = Self.defaultInputDeviceName()
        } catch {
            errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
        }
    }

    private static func defaultInputDeviceName() -> String {
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr else { return "Unknown" }

        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var nameSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &nameAddress, 0, nil, &nameSize) == noErr else {
            return "Unknown"
        }
        var nameData = [UInt8](repeating: 0, count: Int(nameSize))
        let nameStatus = nameData.withUnsafeMutableBytes { ptr in
            AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, ptr.baseAddress!)
        }
        guard nameStatus == noErr else { return "Unknown" }
        let name = nameData.withUnsafeBytes { ptr in
            ptr.load(as: CFString.self)
        }
        return name as String
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
            // Convert to approximate dB SPL: digital 0 dBFS ≈ 90 dB SPL reference
            self.decibelLevel = clampedDb + 90.0
        }
    }
}
