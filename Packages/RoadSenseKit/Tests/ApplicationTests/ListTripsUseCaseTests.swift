import Application
import Domain
import Foundation
import Testing

struct ListTripsUseCaseTests {
    @Test func `returns most recent first`() async throws {
        let older = try Trip(name: "Older", startedAt: .distantPast, distance: .init(value: 1, unit: .kilometers))
        let newer = try Trip(name: "Newer", startedAt: .now, distance: .init(value: 1, unit: .kilometers))
        let listTrips = ListTripsUseCase(repository: StubTripRepository(trips: [older, newer]))

        let trips = try await listTrips()

        #expect(trips.map(\.name) == ["Newer", "Older"])
    }
}

private struct StubTripRepository: TripRepository {
    var trips: [Trip]

    func allTrips() async throws -> [Trip] {
        trips
    }

    func save(_: Trip) async throws {}
}
