import SwiftUI

struct ContentView: View {
    @StateObject private var audioManager = AudioManager()
    @AppStorage("yellowThreshold") private var yellowThresholdDB: Double = 60
    @AppStorage("redThreshold") private var redThresholdDB: Double = 80
    @State private var showSettings = false

    private var yellowNormalized: Float {
        Float((yellowThresholdDB - 34) / 60)
    }

    private var redNormalized: Float {
        Float((redThresholdDB - 34) / 60)
    }

    var body: some View {
        VStack(spacing: 12) {
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

            VolumeMeterView(
                level: audioManager.level,
                yellowThreshold: yellowNormalized,
                redThreshold: redNormalized
            )
            .frame(width: 40, height: 220)

            VStack(spacing: 4) {
                Text(String(format: "%.0f dB SPL", audioManager.decibelLevel))
                    .font(.system(.title2, design: .monospaced))
                    .foregroundColor(.secondary)

                Text(audioManager.deviceName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(action: {
                if audioManager.isMonitoring {
                    audioManager.stopMonitoring()
                } else {
                    audioManager.startMonitoring()
                }
            }) {
                Text(audioManager.isMonitoring ? "Stop" : "Start")
                    .frame(width: 80)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(audioManager.isMonitoring ? .red : .green)

            if let error = audioManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .onAppear {
            audioManager.startMonitoring()
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Thresholds (dB SPL)")
                .font(.headline)

            HStack {
                Text("Yellow:")
                    .frame(width: 50, alignment: .leading)
                Stepper(
                    value: $yellowThresholdDB,
                    in: 34...94,
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
                    in: 34...94,
                    step: 1
                ) {
                    Text("\(Int(redThresholdDB)) dB")
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .padding()
        .frame(width: 220)
    }
}
