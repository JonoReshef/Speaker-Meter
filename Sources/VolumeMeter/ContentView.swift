import SwiftUI

struct ContentView: View {
    @StateObject private var audioManager = AudioManager()
    @StateObject private var paceObserver = SpeechPaceObserver()
    @AppStorage("yellowThreshold") private var yellowThresholdDB: Double = 60
    @AppStorage("redThreshold") private var redThresholdDB: Double = 80
    @AppStorage("yellowWPMThreshold") private var yellowWPMThreshold: Double = 150
    @AppStorage("redWPMThreshold") private var redWPMThreshold: Double = 180
    @State private var showSettings = false

    private let segmentHeight: CGFloat = 10
    private let segmentSpacing: CGFloat = 3
    private let minSegments = 5
    private let maxSegments = 20

    private var yellowNormalized: Float {
        Float((yellowThresholdDB - 30) / 60)
    }

    private var redNormalized: Float {
        Float((redThresholdDB - 30) / 60)
    }

    private func segmentCount(forAvailableHeight height: CGFloat) -> Int {
        let fit = Int((height + segmentSpacing) / (segmentHeight + segmentSpacing))
        return max(minSegments, min(maxSegments, fit))
    }

    private func meterHeight(segments: Int) -> CGFloat {
        CGFloat(segments) * segmentHeight + CGFloat(segments - 1) * segmentSpacing
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSettings, arrowEdge: .top) {
                    settingsContent
                }
            }

            GeometryReader { geo in
                let segments = segmentCount(forAvailableHeight: geo.size.height)
                VolumeMeterView(
                    level: audioManager.level,
                    yellowThreshold: yellowNormalized,
                    redThreshold: redNormalized,
                    segmentCount: segments
                )
                .frame(width: 40, height: meterHeight(segments: segments))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            VStack(spacing: 2) {
                Text(String(format: "%.0f dB SPL", audioManager.decibelLevel))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)

                Text(audioManager.deviceName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .fixedSize(horizontal: false, vertical: true)

            if paceObserver.isAvailable {
                WPMGraphView(
                    history: paceObserver.wpmHistory,
                    maxPoints: 90,
                    yellowThreshold: yellowWPMThreshold,
                    redThreshold: redWPMThreshold
                )
                .frame(height: 50)
            }

            Button(action: {
                if audioManager.isMonitoring {
                    audioManager.stopMonitoring()
                    paceObserver.stopAnalyzing()
                } else {
                    audioManager.startMonitoring()
                    paceObserver.startAnalyzing()
                }
            }) {
                Text(audioManager.isMonitoring ? "Stop" : "Start")
                    .frame(width: 70)
            }
            .controlSize(.regular)
            .buttonStyle(.borderedProminent)
            .tint(audioManager.isMonitoring ? .red : .green)
            .fixedSize(horizontal: false, vertical: true)

            if let error = audioManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .onAppear {
            audioManager.onAudioBuffer = { [weak paceObserver] buffer in
                paceObserver?.processAudioBuffer(buffer)
            }
            audioManager.startMonitoring()
            paceObserver.startAnalyzing()
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Volume Thresholds (dB)")
                .font(.headline)

            HStack {
                Text("Yellow:")
                    .frame(width: 50, alignment: .leading)
                Stepper(
                    value: $yellowThresholdDB,
                    in: 30...90,
                    step: 1
                ) {
                    Text("\(Int(yellowThresholdDB)) dB")
                        .font(.system(.body, design: .monospaced))
                }
            }

            HStack {
                Text("Red:")
                    .frame(width: 50, alignment: .leading)
                Stepper(
                    value: $redThresholdDB,
                    in: 30...90,
                    step: 1
                ) {
                    Text("\(Int(redThresholdDB)) dB")
                        .font(.system(.body, design: .monospaced))
                }
            }

            if paceObserver.isAvailable {
                Divider()

                Text("Pace Thresholds (WPM)")
                    .font(.headline)

                HStack {
                    Text("Yellow:")
                        .frame(width: 50, alignment: .leading)
                    Stepper(
                        value: $yellowWPMThreshold,
                        in: 80...250,
                        step: 5
                    ) {
                        Text("\(Int(yellowWPMThreshold)) WPM")
                            .font(.system(.body, design: .monospaced))
                    }
                }

                HStack {
                    Text("Red:")
                        .frame(width: 50, alignment: .leading)
                    Stepper(
                        value: $redWPMThreshold,
                        in: 80...250,
                        step: 5
                    ) {
                        Text("\(Int(redWPMThreshold)) WPM")
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
        }
        .padding()
        .frame(width: 260)
    }
}
