import SwiftUI

struct VolumeGraphView: View {
    let history: [Double]
    let maxPoints: Int
    var yellowThreshold: Double = 60
    var redThreshold: Double = 80
    var minDB: Double = 30
    var maxDB: Double = 90

    private var dbRange: Double { max(maxDB - minDB, 1) }

    private func colorForDB(_ db: Double) -> Color {
        if db >= redThreshold { return .red }
        if db >= yellowThreshold { return .yellow }
        return .green
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))

                thresholdLine(at: yellowThreshold, color: .yellow, width: w, height: h)
                thresholdLine(at: redThreshold, color: .red, width: w, height: h)

                if history.count >= 2 {
                    let data = Array(history.suffix(maxPoints))
                    let points = graphPoints(data: data, width: w, height: h)

                    ForEach(0..<(points.count - 1), id: \.self) { i in
                        let segmentDB = max(data[i], data[i + 1])
                        let color = colorForDB(segmentDB)

                        Path { path in
                            path.move(to: CGPoint(x: points[i].x, y: h))
                            path.addLine(to: points[i])
                            path.addLine(to: points[i + 1])
                            path.addLine(to: CGPoint(x: points[i + 1].x, y: h))
                            path.closeSubpath()
                        }
                        .fill(color.opacity(0.2))

                        Path { path in
                            path.move(to: points[i])
                            path.addLine(to: points[i + 1])
                        }
                        .stroke(color, lineWidth: 1.5)
                    }
                }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        let db = history.last ?? 0
                        let labelColor = db > 0 ? colorForDB(db) : .green
                        Text(db > 0 ? String(format: "%.0f", db) : "--")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(labelColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
                            .cornerRadius(3)
                    }
                }
                .padding(3)

                VStack {
                    HStack {
                        Text("dB")
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

    private func normalizedY(_ db: Double, height: CGFloat) -> CGFloat {
        let clamped = min(max(db, minDB), maxDB)
        return height * (1 - (clamped - minDB) / dbRange)
    }

    private func graphPoints(data: [Double], width: CGFloat, height: CGFloat) -> [CGPoint] {
        let step = width / CGFloat(maxPoints - 1)
        let offset = CGFloat(maxPoints - data.count)
        return data.enumerated().map { i, db in
            let x = (offset + CGFloat(i)) * step
            let y = normalizedY(db, height: height)
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
