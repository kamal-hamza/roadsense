import Application
import Domain
import Foundation
@testable import Presentation
import SensorCore
import SensorRecording
import Testing

struct DriveViewModelTests {
    private static let origin = Coordinate(latitude: 47.6, longitude: -122.3)

    private func makeViewModel() throws -> DriveViewModel {
        let end = Self.origin.offset(by: 1500, toward: Bearing(degrees: 0))
        let route = try Route(name: "Test Rd", points: [Self.origin, end], expectedTravelTime: 120)
        let plan = TripPlan(
            destination: Place(name: "End", coordinate: end),
            route: route,
            hotspots: [],
            freshness: .live,
        )
        let recordTrip = RecordTripUseCase(
            recorder: SensorRecorder(
                sensorSource: OpenEndedSensorSource(start: Self.origin),
                sensorLogStore: NoSensorLog(),
            ),
            tripRepository: NoTripRepository(),
        )
        let driveTrip = DriveTripUseCase(
            recordTrip: recordTrip,
            tripLogStore: NoTripLogStore(),
            alerting: SilentAlerting(),
            directions: NoDirections(),
            findHotspots: FindRouteHotspotsUseCase(service: NoHotspots(), cache: NoHotspotCache(), retryDelays: []),
        )
        return DriveViewModel(plan: plan, driveTrip: driveTrip)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0 ..< 200 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func `drives, mutes, and ends when the driver says so`() async throws {
        let viewModel = try makeViewModel()
        let drive = Task { await viewModel.run() }

        try await waitUntil {
            if case .driving = viewModel.state {
                true
            } else {
                false
            }
        }
        await viewModel.toggleMute()
        try await waitUntil { viewModel.isMuted }
        let wasMuted = viewModel.isMuted
        await viewModel.end()
        try await waitUntil {
            if case .ended = viewModel.state {
                true
            } else {
                false
            }
        }
        drive.cancel()

        #expect(wasMuted)
        guard case let .ended(log) = viewModel.state else {
            Issue.record("Expected .ended, got \(viewModel.state)")
            return
        }
        #expect(log.endReason == .endedByDriver)
        #expect(log.entries.contains { $0.event == .muted })
    }
}

/// Sends a few GPS fixes heading north, then stays open like live sensors until the drive stops it.
private struct OpenEndedSensorSource: SensorSource {
    let start: Coordinate

    func readings(configuration _: SensorConfiguration) async -> AsyncStream<SensorReading> {
        let start = start
        return AsyncStream { continuation in
            for second in 0 ..< 5 {
                continuation.yield(.location(LocationSample(
                    timestamp: Date().addingTimeInterval(Double(second)),
                    coordinate: start.offset(by: Double(second) * 15, toward: Bearing(degrees: 0)),
                    horizontalAccuracy: 5,
                    speed: 15,
                    speedAccuracy: 0.5,
                    course: 0,
                    courseAccuracy: 5,
                )))
            }
        }
    }
}

private struct NoSensorLog: SensorLogStore {
    func beginLog(recordingID _: UUID) async throws {}
    func append(_: [SensorReading]) async throws {}
    func finishLog() async throws {}
    func logURL(recordingID _: UUID) async -> URL? {
        nil
    }
}

private struct NoTripRepository: TripRepository {
    func allTrips() async throws -> [Trip] {
        []
    }

    func save(_: Trip) async throws {}
}

private struct NoTripLogStore: TripLogStore {
    func begin(_: TripLog) async throws {}
    func append(_: TripLogEntry) async throws {}
    func finish(at _: Date, reason _: TripEndReason, endCoordinate _: Coordinate?) async throws {}
    func unfinishedLog() async throws -> TripLog? {
        nil
    }

    func finishedLogs() async throws -> [TripLog] {
        []
    }

    func saveFinished(_: TripLog) async throws {}
    func deleteFinished(id _: TripLog.ID) async throws {}
}

private struct SilentAlerting: DriveAlerting {
    func prepare() async {}
    func announce(_: DriveWarning) async {}
}

private struct NoDirections: DirectionsProviding {
    func routes(from _: Coordinate, to _: Place) async throws -> [Route] {
        []
    }
}

private struct NoHotspots: HotspotService {
    func hotspots(along _: Route) async throws -> [RouteHotspot] {
        []
    }
}

private struct NoHotspotCache: HotspotCache {
    func save(_: CachedHotspotArea) async throws {}
    func areas() async throws -> [CachedHotspotArea] {
        []
    }
}
