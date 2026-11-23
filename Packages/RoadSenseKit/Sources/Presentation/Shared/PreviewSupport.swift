import Application
import Domain
import Foundation
import SensorCore
import SensorRecording

// Preview-only fakes. Not `#if DEBUG` because Release builds type-check `#Preview` too.

struct PreviewTripRepository: TripRepository {
    var trips: [Trip]

    func allTrips() async throws -> [Trip] {
        trips
    }

    func save(_: Trip) async throws {}
}

/// A sensor source that never produces readings.
struct PreviewSensorSource: SensorSource {
    func readings(configuration _: SensorConfiguration) async -> AsyncStream<SensorReading> {
        AsyncStream { $0.finish() }
    }
}

struct PreviewSensorLogStore: SensorLogStore {
    func beginLog(recordingID _: UUID) async throws {}
    func append(_: [SensorReading]) async throws {}
    func finishLog() async throws {}
    func logURL(recordingID _: UUID) async -> URL? {
        nil
    }
}

extension DrivingEvent {
    static let previewSamples: [DrivingEvent] = [
        DrivingEvent(
            kind: .hardBrake,
            timestamp: .now.addingTimeInterval(-3000),
            duration: 1.2,
            peakAcceleration: 0.47,
            speed: 17,
            course: 90,
            coordinate: Coordinate(latitude: 47.61, longitude: -122.33),
            confidence: 0.9,
        ),
        DrivingEvent(
            kind: .sharpTurn,
            timestamp: .now.addingTimeInterval(-2800),
            duration: 2.5,
            peakAcceleration: 0.41,
            speed: 12,
            course: 180,
            coordinate: Coordinate(latitude: 47.62, longitude: -122.34),
            confidence: 1,
        ),
    ]
}

extension Trip {
    static let previewSamples: [Trip] = [
        try? Trip(
            name: "Morning commute",
            startedAt: .now.addingTimeInterval(-3600),
            endedAt: .now.addingTimeInterval(-2400),
            distance: .init(value: 18.4, unit: .kilometers),
            events: DrivingEvent.previewSamples,
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
        let repository = PreviewTripRepository(trips: trips)
        let logStore = PreviewSensorLogStore()
        return AppDependencies(
            listTrips: ListTripsUseCase(repository: repository),
            recordTrip: RecordTripUseCase(
                recorder: SensorRecorder(sensorSource: PreviewSensorSource(), sensorLogStore: logStore),
                tripRepository: repository,
            ),
            findSensorLog: FindSensorLogUseCase(store: logStore),
        )
    }
}
