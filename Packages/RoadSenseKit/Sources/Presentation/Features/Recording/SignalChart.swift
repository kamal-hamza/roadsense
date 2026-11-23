import Charts
import SwiftUI

/// Live chart of the car's forward, sideways, and vertical acceleration.
struct SignalChart: View {
    let points: [RecordingViewModel.ChartPoint]

    var body: some View {
        Chart(points) { point in
            LineMark(
                x: .value("Time", point.time),
                y: .value("Acceleration (g)", point.value),
                // series groups points into one line per signal instead of a single zig-zag.
                series: .value("Signal", point.signal.rawValue),
            )
            .foregroundStyle(by: .value("Signal", point.signal.rawValue))
            .interpolationMethod(.linear)
        }
        // Fixed ±1 g scale so the chart doesn't jump around as values change.
        .chartYScale(domain: -1 ... 1)
        .chartXAxis(.hidden)
        .chartYAxisLabel("g")
        .frame(height: 180)
        .accessibilityLabel("Live acceleration chart")
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        RecordingViewModel.Signal.allCases.compactMap { signal in
            guard let latest = points.last(where: { $0.signal == signal }) else { return nil }
            return "\(signal.rawValue) \(latest.value.formatted(.number.precision(.fractionLength(2)))) g"
        }.joined(separator: ", ")
    }
}

#Preview {
    let start = Date.now
    let points = (0 ..< 100).flatMap { index in
        let time = start.addingTimeInterval(Double(index) / 10)
        return [
            RecordingViewModel.ChartPoint(
                id: index * 3,
                time: time,
                signal: .forward,
                value: sin(Double(index) / 8) * 0.3,
            ),
            RecordingViewModel.ChartPoint(
                id: index * 3 + 1,
                time: time,
                signal: .sideways,
                value: cos(Double(index) / 12) * 0.2,
            ),
            RecordingViewModel.ChartPoint(id: index * 3 + 2, time: time, signal: .vertical, value: 0.02),
        ]
    }
    SignalChart(points: points).padding()
}
