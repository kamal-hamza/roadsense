import Domain
import Foundation
import Infrastructure
import Testing

struct InMemoryTripRepositoryTests {
    @Test func `save then fetch`() async throws {
        let repository = InMemoryTripRepository()
        let trip = try Trip(name: "Commute", startedAt: .now, distance: .init(value: 5, unit: .kilometers))

        await repository.save(trip)

        #expect(await repository.allTrips() == [trip])
    }

    @Test func `save replaces existing trip`() async throws {
        let id = UUID()
        let original = try Trip(id: id, name: "Draft", startedAt: .now, distance: .init(value: 1, unit: .kilometers))
        let updated = try Trip(id: id, name: "Final", startedAt: .now, distance: .init(value: 2, unit: .kilometers))
        let repository = InMemoryTripRepository(trips: [original])

        await repository.save(updated)

        #expect(await repository.allTrips().map(\.name) == ["Final"])
    }
}
