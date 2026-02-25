import SwiftUI

struct ContentView: View {
    @StateObject private var audioManager = AudioManager()

    var body: some View {
        VStack(spacing: 20) {
            Text("Volume Meter")
                .font(.title.bold())

            VolumeMeterView(level: audioManager.level)
                .frame(width: 40, height: 220)

            Text(String(format: "%.0f dB SPL", audioManager.decibelLevel))
                .font(.system(.title2, design: .monospaced))
                .foregroundColor(.secondary)

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
        .padding(30)
        .frame(minWidth: 300, minHeight: 400)
        .onAppear {
            audioManager.startMonitoring()
        }
    }
}
