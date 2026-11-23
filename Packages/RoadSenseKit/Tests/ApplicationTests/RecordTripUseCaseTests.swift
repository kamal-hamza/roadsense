import Application
import Domain
import DriveSimulation
import Foundation
import SensorCore
import SensorRecording
import Testing

struct RecordTripUseCaseTests {
    @Test func `saves the recording as a trip`() async throws {
        let readings = SyntheticDrive(
            segments: DriveSegment.warmUp + [.brake(g: 0.45, seconds: 1.5), .cruise(seconds: 4)],
        ).readings()
        let repository = SpyTripRepository()
        let recordTrip = RecordTripUseCase(
            recorder: SensorRecorder(sensorSource: StubSensorSource(readings: readings), sensorLogStore: NoLogStore()),
            tripRepository: repository,
        )

        let snapshots = try await recordTrip.start(logsRawSensors: false)
        var recordingID: UUID?
        for await snapshot in snapshots {
            recordingID = snapshot.recordingID
        }
        let trip = try await recordTrip.stop()

        #expect(trip.id == recordingID)
        #expect(trip.events.map(\.kind) == [.hardBrake])
        #expect(trip.distance.converted(to: .meters).value > 300)
        #expect(trip.endedAt != nil)
        #expect(await repository.savedTrips == [trip])
    }
}

private actor SpyTripRepository: TripRepository {
    private(set) var savedTrips: [Trip] = []

    func allTrips() -> [Trip] {
        savedTrips
    }

    func save(_ trip: Trip) {
        savedTrips.append(trip)
    }
}

private struct StubSensorSource: SensorSource {
    let readings: [SensorReading]

    func readings(configuration _: SensorConfiguration) async -> AsyncStream<SensorReading> {
        AsyncStream { continuation in
            for reading in readings {
                continuation.yield(reading)
            }
            continuation.finish()
        }
    }
}

private struct NoLogStore: SensorLogStore {
    func beginLog(recordingID _: UUID) async throws {}
    func append(_: [SensorReading]) async throws {}
    func finishLog() async throws {}
    func logURL(recordingID _: UUID) async -> URL? {
        nil
    }
}
