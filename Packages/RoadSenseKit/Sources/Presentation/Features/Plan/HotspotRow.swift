import Domain
import SwiftUI

/// One hotspot on the route: what it is, how far from the start, and how many drivers flagged it.
struct HotspotRow: View {
    let routeHotspot: RouteHotspot

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(routeHotspot.hotspot.kind.title)
                    .font(.headline)
                Group {
                    Text("\(distanceFromStart) from start")
                    Text("Flagged by ^[\(routeHotspot.hotspot.driverCount) driver](inflect: true)")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: routeHotspot.hotspot.kind.systemImage)
                .foregroundStyle(.orange)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var distanceFromStart: String {
        Measurement(value: routeHotspot.distanceAlongRoute, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}
