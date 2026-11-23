import SensorCore
import SwiftUI

/// One detected driving event in a list.
struct EventRow: View {
    let event: DrivingEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.kind.systemImage)
                .foregroundStyle(.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.kind.title)
                    .font(.headline)
                Text(event.timestamp, format: .dateTime.hour().minute().second())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(event.peakAcceleration, format: .number.precision(.fractionLength(2))) g")
                    .font(.subheadline.monospacedDigit())
                if let speed = event.speed {
                    Text(Measurement(value: speed, unit: UnitSpeed.metersPerSecond), format: .speed)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension FormatStyle where Self == Measurement<UnitSpeed>.FormatStyle {
    /// Road speed in the user's preferred unit (km/h or mph), no decimals.
    static var speed: Self {
        .measurement(width: .abbreviated, usage: .general, numberFormatStyle: .number.precision(.fractionLength(0)))
    }
}
