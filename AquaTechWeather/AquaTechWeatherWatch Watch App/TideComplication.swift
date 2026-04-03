import WidgetKit
import SwiftUI
import Charts

// MARK: - Tide Complication Entry

struct TideEntry: TimelineEntry {
    let date: Date
    let tideCurve: [TidePoint]
    let nextTide: String  // e.g. "High 2:30 PM"
    let currentLevel: String  // e.g. "2.1 ft"

    static let placeholder = TideEntry(
        date: Date(),
        tideCurve: [],
        nextTide: "High 2:30 PM",
        currentLevel: "2.1 ft"
    )
}

// MARK: - Tide Complication Views

struct TideInlineView: View {
    let entry: TideEntry

    var body: some View {
        Text("🌊 \(entry.nextTide)")
    }
}

struct TideCornerView: View {
    let entry: TideEntry

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "water.waves")
                .font(.caption)
            Text(entry.currentLevel)
                .font(.system(size: 10, weight: .bold))
        }
    }
}

struct TideRectangularView: View {
    let entry: TideEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "water.waves")
                    .font(.caption2)
                    .foregroundStyle(.cyan)
                Text("Tides")
                    .font(.caption2.bold())
                Spacer()
                Text(entry.nextTide)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            if !entry.tideCurve.isEmpty {
                Chart {
                    ForEach(entry.tideCurve) { point in
                        AreaMark(
                            x: .value("Time", point.date),
                            y: .value("Level", point.level)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan.opacity(0.3), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Time", point.date),
                            y: .value("Level", point.level)
                        )
                        .foregroundStyle(.cyan)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }

                    RuleMark(x: .value("Now", Date()))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
            }
        }
    }
}
