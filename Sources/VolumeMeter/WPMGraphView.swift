import SwiftUI

struct WPMGraphView: View {
    let history: [Double]
    let maxPoints: Int
    var yellowThreshold: Double = 150
    var redThreshold: Double = 180
    var minWPM: Double = 0
    var maxWPM: Double = 250

    private var wpmRange: Double { max(maxWPM - minWPM, 1) }

    private func colorForWPM(_ wpm: Double) -> Color {
        if wpm >= redThreshold { return .red }
        if wpm >= yellowThreshold { return .yellow }
        return .green
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))

                // Threshold lines
                thresholdLine(at: yellowThreshold, color: .yellow, width: w, height: h)
                thresholdLine(at: redThreshold, color: .red, width: w, height: h)

                // Per-segment colored graph
                if history.count >= 2 {
                    let data = Array(history.suffix(maxPoints))
                    let points = graphPoints(data: data, width: w, height: h)

                    // Draw each segment with the color of its higher-WPM endpoint
                    ForEach(0..<(points.count - 1), id: \.self) { i in
                        let segmentWPM = max(data[i], data[i + 1])
                        let color = colorForWPM(segmentWPM)

                        // Filled area for this segment
                        Path { path in
                            path.move(to: CGPoint(x: points[i].x, y: h))
                            path.addLine(to: points[i])
                            path.addLine(to: points[i + 1])
                            path.addLine(to: CGPoint(x: points[i + 1].x, y: h))
                            path.closeSubpath()
                        }
                        .fill(color.opacity(0.2))

                        // Line segment
                        Path { path in
                            path.move(to: points[i])
                            path.addLine(to: points[i + 1])
                        }
                        .stroke(color, lineWidth: 1.5)
                    }
                }

                // Current WPM label
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        let wpm = history.last ?? 0
                        let labelColor = wpm > 0 ? colorForWPM(wpm) : .green
                        Text(wpm > 0 ? String(format: "%.0f", wpm) : "--")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(labelColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
                            .cornerRadius(3)
                    }
                }
                .padding(3)

                // "WPM" label
                VStack {
                    HStack {
                        Text("WPM")
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(3)
            }
        }
    }

    private func normalizedY(_ wpm: Double, height: CGFloat) -> CGFloat {
        let clamped = min(max(wpm, minWPM), maxWPM)
        return height * (1 - (clamped - minWPM) / wpmRange)
    }

    private func graphPoints(data: [Double], width: CGFloat, height: CGFloat) -> [CGPoint] {
        let step = width / CGFloat(maxPoints - 1)
        let offset = CGFloat(maxPoints - data.count)
        return data.enumerated().map { i, wpm in
            let x = (offset + CGFloat(i)) * step
            let y = normalizedY(wpm, height: height)
            return CGPoint(x: x, y: y)
        }
    }

    private func thresholdLine(at value: Double, color: Color, width: CGFloat, height: CGFloat) -> some View {
        let y = normalizedY(value, height: height)
        return Path { path in
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: width, y: y))
        }
        .stroke(color.opacity(0.3), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
    }
}
