import Domain
import Foundation
import SensorRecording

/// Starts the sensor recorder and saves the finished recording as a `Trip`.
public struct RecordTripUseCase: Sendable {
    private let recorder: SensorRecorder
    private let tripRepository: any TripRepository

    public init(recorder: SensorRecorder, tripRepository: any TripRepository) {
        self.recorder = recorder
        self.tripRepository = tripRepository
    }

    /// Starts recording and returns live snapshots for display.
    public func start(logsRawSensors: Bool) async throws(SensorRecorderError) -> AsyncStream<RecordingSnapshot> {
        try await recorder.start(options: SensorRecorder.Options(logsRawSensors: logsRawSensors))
    }

    /// Stops recording, saves the trip, and returns it.
    public func stop() async throws -> Trip {
        // The sensor package knows nothing about trips; this is where its output becomes one.
        let summary = try await recorder.stop()
        let trip = try Trip(
            id: summary.id,
            name: "Drive · " + summary.startedAt.formatted(date: .abbreviated, time: .shortened),
            startedAt: summary.startedAt,
            endedAt: summary.endedAt,
            distance: Measurement(value: summary.distanceMeters, unit: .meters),
            events: summary.events,
        )
        try await tripRepository.save(trip)
        return trip
    }
}
