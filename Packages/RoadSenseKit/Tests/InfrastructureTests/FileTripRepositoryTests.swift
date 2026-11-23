import Domain
import Foundation
import Infrastructure
import SensorCore
import Testing

struct FileTripRepositoryTests {
    @Test func `persists trips across instances`() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "File TripRepository Tests-\(UUID().uuidString)/trips.json")
        let event = DrivingEvent(
            kind: .bump,
            timestamp: .now,
            duration: 0.1,
            peakAcceleration: 0.8,
            speed: 12,
            course: nil,
            coordinate: nil,
            confidence: 1,
        )
        let trip = try Trip(
            name: "Commute",
            startedAt: .now,
            distance: .init(value: 3, unit: .kilometers),
            events: [event],
        )

        try await FileTripRepository(fileURL: fileURL).save(trip)
        let reloaded = try await FileTripRepository(fileURL: fileURL).allTrips()

        #expect(reloaded == [trip])
    }

    @Test func `starts empty when no file exists`() async throws {
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString).json")

        #expect(try await FileTripRepository(fileURL: fileURL).allTrips().isEmpty)
    }
}
