import Application
import Domain
import Foundation
@testable import Presentation
import SensorCore
import SensorRecording
import Testing

struct RecordingViewModelTests {
    @Test func `starts, shows live data, and saves on stop`() async throws {
        let motion = MotionSample(
            timestamp: .now,
            gravity: SIMD3(0, 0, -1),
            userAcceleration: SIMD3(0, 0, 0.05),
            rotationRate: .zero,
        )
        let viewModel = makeViewModel(readings: Array(repeating: .motion(motion), count: 3))

        await viewModel.start()
        #expect(viewModel.phase == .recording)
        try await waitUntil { viewModel.snapshot != nil }
        #expect(viewModel.chartPoints.contains { $0.signal == .vertical })

        await viewModel.stop()

        #expect(viewModel.phase == .idle)
        #expect(viewModel.lastSavedTrip != nil)
        #expect(viewModel.canStart)
    }

    @Test func `ignores stop when not recording`() async {
        let viewModel = makeViewModel(readings: [])

        await viewModel.stop()

        #expect(viewModel.phase == .idle)
        #expect(viewModel.lastSavedTrip == nil)
    }

    private func makeViewModel(readings: [SensorReading]) -> RecordingViewModel {
        RecordingViewModel(recordTrip: RecordTripUseCase(
            recorder: SensorRecorder(sensorSource: StubSensorSource(readings: readings), sensorLogStore: NoLogStore()),
            tripRepository: InMemoryRepository(),
        ))
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0 ..< 100 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
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

private actor InMemoryRepository: TripRepository {
    private var trips: [Trip] = []

    func allTrips() -> [Trip] {
        trips
    }

    func save(_ trip: Trip) {
        trips.append(trip)
    }
}
