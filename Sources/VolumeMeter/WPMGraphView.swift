import SwiftUI

struct WPMGraphView: View {
    let history: [Double]
    let maxPoints: Int
    var yellowThreshold: Double = 150
    var redThreshold: Double = 180

    private let maxWPM: Double = 250

    private var currentColor: Color {
        guard let last = history.last, last > 0 else { return .green }
        if last >= redThreshold { return .red }
        if last >= yellowThreshold { return .yellow }
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

                // Graph area fill + line
                if history.count >= 2 {
                    let points = graphPoints(width: w, height: h)

                    // Filled area
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: h))
                        for pt in points {
                            path.addLine(to: pt)
                        }
                        path.addLine(to: CGPoint(x: points.last!.x, y: h))
                        path.closeSubpath()
                    }
                    .fill(currentColor.opacity(0.2))

                    // Line
                    Path { path in
                        path.move(to: points[0])
                        for pt in points.dropFirst() {
                            path.addLine(to: pt)
                        }
                    }
                    .stroke(currentColor, lineWidth: 1.5)
                }

                // Current WPM label
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        let wpm = history.last ?? 0
                        Text(wpm > 0 ? String(format: "%.0f", wpm) : "--")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(currentColor)
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

    private func graphPoints(width: CGFloat, height: CGFloat) -> [CGPoint] {
        let data = Array(history.suffix(maxPoints))
        let step = width / CGFloat(maxPoints - 1)
        let offset = CGFloat(maxPoints - data.count)
        return data.enumerated().map { i, wpm in
            let x = (offset + CGFloat(i)) * step
            let clamped = min(wpm, maxWPM)
            let y = height * (1 - clamped / maxWPM)
            return CGPoint(x: x, y: y)
        }
    }

    private func thresholdLine(at value: Double, color: Color, width: CGFloat, height: CGFloat) -> some View {
        let y = height * (1 - value / maxWPM)
        return Path { path in
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: width, y: y))
        }
        .stroke(color.opacity(0.3), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
    }
}
