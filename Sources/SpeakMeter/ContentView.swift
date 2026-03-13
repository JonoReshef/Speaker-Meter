import Combine
import SwiftUI

struct ContentView: View {
    @StateObject private var audioManager = AudioManager()
    @StateObject private var paceAnalyzer = AcousticPaceAnalyzer()
    @State private var historyTimer: AnyCancellable?
    @AppStorage("yellowThreshold") private var yellowThresholdDB: Double = 60
    @AppStorage("redThreshold") private var redThresholdDB: Double = 80
    @AppStorage("yellowWPMThreshold") private var yellowWPMThreshold: Double = 150
    @AppStorage("redWPMThreshold") private var redWPMThreshold: Double = 180
    @AppStorage("minWPM") private var minWPM: Double = 80
    @AppStorage("maxWPM") private var maxWPM: Double = 250
    @State private var showSettings = false
    @AppStorage("showVolumeGraph") private var showVolumeGraph: Bool = false

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

            if showVolumeGraph {
                VolumeGraphView(
                    history: audioManager.decibelHistory,
                    maxPoints: 90,
                    yellowThreshold: yellowThresholdDB,
                    redThreshold: redThresholdDB
                )
                .frame(maxWidth: .infinity)
                .frame(height: 80)
            } else {
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
            }

            HStack(spacing: 4) {
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

                Button(action: { showVolumeGraph.toggle() }) {
                    Image(systemName: showVolumeGraph ? "chart.bar.fill" : "chart.line.uptrend.xyaxis")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(showVolumeGraph ? "Show bar meter" : "Show volume graph")
            }
            .fixedSize(horizontal: false, vertical: true)

            WPMGraphView(
                history: paceAnalyzer.wpmHistory,
                maxPoints: 90,
                yellowThreshold: yellowWPMThreshold,
                redThreshold: redWPMThreshold,
                minWPM: minWPM,
                maxWPM: maxWPM
            )
            .frame(height: 50)

            Button(action: {
                if audioManager.isMonitoring {
                    audioManager.stopMonitoring()
                    paceAnalyzer.stopAnalyzing()
                    stopSharedHistoryTimer()
                } else {
                    audioManager.startMonitoring()
                    paceAnalyzer.startAnalyzing()
                    startSharedHistoryTimer()
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
            audioManager.onAudioBuffer = { [weak paceAnalyzer] buffer in
                paceAnalyzer?.processAudioBuffer(buffer)
            }
            audioManager.startMonitoring()
            paceAnalyzer.startAnalyzing()
            startSharedHistoryTimer()
        }
    }

    private func startSharedHistoryTimer() {
        historyTimer?.cancel()
        historyTimer = Timer.publish(every: 1.0 / 3.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak audioManager, weak paceAnalyzer] _ in
                audioManager?.appendDecibelToHistory()
                paceAnalyzer?.appendToHistory()
            }
    }

    private func stopSharedHistoryTimer() {
        historyTimer?.cancel()
        historyTimer = nil
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

            Divider()

            Text("Pace Graph Range (WPM)")
                .font(.headline)

            HStack {
                Text("Min:")
                    .frame(width: 50, alignment: .leading)
                Stepper(
                    value: $minWPM,
                    in: 0...(maxWPM - 10),
                    step: 10
                ) {
                    Text("\(Int(minWPM)) WPM")
                        .font(.system(.body, design: .monospaced))
                }
            }

            HStack {
                Text("Max:")
                    .frame(width: 50, alignment: .leading)
                Stepper(
                    value: $maxWPM,
                    in: (minWPM + 10)...400,
                    step: 10
                ) {
                    Text("\(Int(maxWPM)) WPM")
                        .font(.system(.body, design: .monospaced))
                }
            }

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
        .padding()
        .frame(width: 260)
    }
}
