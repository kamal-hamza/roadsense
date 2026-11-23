import Domain
import SwiftUI

/// One route option: its name, driving time, and length.
struct RouteOptionRow: View {
    let route: Route
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    Duration.seconds(route.expectedTravelTime),
                    format: .units(allowed: [.hours, .minutes], width: .abbreviated),
                )
                .font(.headline)
                HStack(spacing: 4) {
                    Text(
                        Measurement(value: route.length, unit: UnitLength.meters),
                        format: .measurement(width: .abbreviated, usage: .road),
                    )
                    if !route.name.isEmpty {
                        Text("via \(route.name)")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer()
            // A checkmark, not just color, shows which route is chosen.
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
