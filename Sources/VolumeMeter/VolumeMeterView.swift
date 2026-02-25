import SwiftUI

struct VolumeMeterView: View {
    let level: Float
    var yellowThreshold: Float = 0.6
    var redThreshold: Float = 0.8
    private let segmentCount = 20

    var body: some View {
        VStack(spacing: 3) {
            ForEach((0..<segmentCount).reversed(), id: \.self) { index in
                let threshold = Float(index) / Float(segmentCount)
                let isActive = level > threshold

                RoundedRectangle(cornerRadius: 2)
                    .fill(isActive ? colorForSegment(index) : Color.gray.opacity(0.3))
                    .frame(height: 10)
            }
        }
        .animation(.easeOut(duration: 0.05), value: level)
    }

    private func colorForSegment(_ index: Int) -> Color {
        let position = Float(index) / Float(segmentCount)
        if position < yellowThreshold {
            return .green
        } else if position < redThreshold {
            return .yellow
        } else {
            return .red
        }
    }
}
