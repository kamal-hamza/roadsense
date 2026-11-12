import Application
import Domain
import Foundation

// Preview-only fakes. Presentation can't import Infrastructure, so previews
// use these instead of real repositories.
//
// Not wrapped in `#if DEBUG`: `#Preview` bodies are type-checked in Release builds too.

struct PreviewTripRepository: TripRepository {
    var trips: [Trip]

    func allTrips() async throws -> [Trip] {
        trips
    }

    func save(_: Trip) async throws {}
}

extension Trip {
    static let previewSamples: [Trip] = [
        try? Trip(
            name: "Morning commute",
            startedAt: .now.addingTimeInterval(-3600),
            distance: .init(value: 18.4, unit: .kilometers),
        ),
        try? Trip(
            name: "Weekend drive",
            startedAt: .now.addingTimeInterval(-86400 * 2),
            distance: .init(value: 112, unit: .kilometers),
        ),
    ].compactMap(\.self)
}

extension AppDependencies {
    static let preview = preview(trips: Trip.previewSamples)

    static func preview(trips: [Trip]) -> AppDependencies {
        AppDependencies(listTrips: ListTripsUseCase(repository: PreviewTripRepository(trips: trips)))
    }
}
