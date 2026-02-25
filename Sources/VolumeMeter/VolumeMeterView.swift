import SwiftUI

struct VolumeMeterView: View {
    let level: Float
    private let segmentCount = 20

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<segmentCount, id: \.self) { index in
                let threshold = Float(index) / Float(segmentCount)
                let isActive = level > threshold

                RoundedRectangle(cornerRadius: 2)
                    .fill(isActive ? colorForSegment(index) : Color.gray.opacity(0.3))
                    .frame(width: 16)
            }
        }
        .animation(.easeOut(duration: 0.05), value: level)
    }

    private func colorForSegment(_ index: Int) -> Color {
        let position = Float(index) / Float(segmentCount)
        if position < 0.6 {
            return .green
        } else if position < 0.8 {
            return .yellow
        } else {
            return .red
        }
    }
}
