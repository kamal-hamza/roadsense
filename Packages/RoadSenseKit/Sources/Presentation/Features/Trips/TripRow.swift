import Domain
import SwiftUI

/// One row in the trip list.
struct TripRow: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(trip.name)
                .font(.headline)
            HStack {
                Text(trip.startedAt, format: .dateTime.month().day().hour().minute())
                Spacer()
                Text("^[\(trip.events.count) event](inflect: true)")
                Text(trip.distance, format: .measurement(width: .abbreviated, usage: .road))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
