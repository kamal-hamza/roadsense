import Application
import Domain
import DriveSimulation
import Foundation
import SensorCore
import SensorRecording
import Testing

/// End to end through the real recorder and detectors: a synthetic car drives a route with two hotspots.
struct DriveTripUseCaseTests {
    private static let origin = Coordinate(latitude: 47.6, longitude: -122.3)
    private static let north = Bearing(degrees: 0)

    private let plan: TripPlan

    init() throws {
        let points = stride(from: 0.0, through: 1500, by: 100).map { Self.origin.offset(by: $0, toward: Self.north) }
        let route = try Route(name: "Test Rd", points: points, expectedTravelTime: 120)
        let hotspots = [600.0, 1100].map { distance in
            RouteHotspot(
                hotspot: Hotspot(
                    id: UUID(),
                    kind: .suddenStop,
                    coordinate: Self.origin.offset(by: distance, toward: Self.north),
                    bearing: Self.north,
                    driverCount: 5,
                ),
                distanceAlongRoute: distance,
            )
        }
        plan = TripPlan(
            destination: Place(name: "End", coordinate: points[points.count - 1]),
            route: route,
            hotspots: hotspots,
            freshness: .live,
        )
    }

    private func makeUseCase(
        readings: [SensorReading],
        alerts: RecordingAlerts,
        logStore: MemoryTripLogStore,
        warningsEnabled: Bool = true,
    ) -> DriveTripUseCase {
        let repository = MemoryTripRepository()
        return DriveTripUseCase(
            recordTrip: RecordTripUseCase(
                recorder: SensorRecorder(
                    sensorSource: PacedSensorSource(readings: readings),
                    sensorLogStore: NoSensorLog(),
                ),
                tripRepository: repository,
            ),
            tripLogStore: logStore,
            alerting: alerts,
            directions: NoDirections(),
            findHotspots: FindRouteHotspotsUseCase(
                service: NoHotspotService(),
                cache: NoHotspotCache(),
                retryDelays: [],
            ),
            preferences: FixedPreferences(preferences: AppPreferences(warningsEnabled: warningsEnabled)),
        )
    }

    @Test func `drives the route, warns before both hotspots, and ends on arrival`() async throws {
        let drive = SyntheticDrive(
            segments: [.parked(seconds: 2), .followPath(plan.route.points, cruiseSpeed: 13), .parked(seconds: 35)],
            startCoordinate: Self.origin,
        )
        let alerts = RecordingAlerts()
        let logStore = MemoryTripLogStore()
        let driveTrip = makeUseCase(readings: drive.readings(), alerts: alerts, logStore: logStore)

        var finalState: DriveState?
        for await state in try await driveTrip.start(plan) {
            finalState = state
        }

        guard case let .ended(log) = finalState else {
            Issue.record("Expected the drive to end, got \(String(describing: finalState))")
            return
        }
        #expect(log.endReason == .arrived)
        // Permission is asked alongside the drive, so it's done long before the drive ends.
        #expect(await alerts.prepared)
        #expect(await alerts.warnings.flatMap { $0.hotspots.map(\.id) } == plan.hotspots.map(\.id))
        let passes = log.entries.filter {
            if case .hotspotPassed = $0.event {
                true
            } else {
                false
            }
        }
        #expect(passes.count == 2)
        #expect(await logStore.finishedReason == .arrived)
        #expect(await logStore.appended.count == log.entries.count)
    }

    @Test func `with warnings turned off in Settings the drive starts muted and never speaks`() async throws {
        let drive = SyntheticDrive(
            segments: [.parked(seconds: 2), .followPath(plan.route.points, cruiseSpeed: 13), .parked(seconds: 35)],
            startCoordinate: Self.origin,
        )
        let alerts = RecordingAlerts()
        let driveTrip = makeUseCase(
            readings: drive.readings(),
            alerts: alerts,
            logStore: MemoryTripLogStore(),
            warningsEnabled: false,
        )

        var finalState: DriveState?
        for await state in try await driveTrip.start(plan) {
            finalState = state
        }

        guard case let .ended(log) = finalState else {
            Issue.record("Expected the drive to end, got \(String(describing: finalState))")
            return
        }
        #expect(log.entries.first?.event == .muted)
        #expect(await alerts.warnings.isEmpty)
    }

    @Test func `the driver can end early, and can't start a second drive meanwhile`() async throws {
        let drive = SyntheticDrive(
            segments: [.parked(seconds: 2), .followPath(plan.route.points, cruiseSpeed: 13)],
            startCoordinate: Self.origin,
        )
        let driveTrip = makeUseCase(
            readings: drive.readings(),
            alerts: RecordingAlerts(),
            logStore: MemoryTripLogStore(),
        )
        let states = try await driveTrip.start(plan)

        await #expect(throws: DriveTripUseCase.DriveError.alreadyDriving) {
            _ = try await driveTrip.start(plan)
        }
        await driveTrip.end()
        var finalState: DriveState?
        for await state in states {
            finalState = state
        }

        guard case let .ended(log) = finalState else {
            Issue.record("Expected the drive to end, got \(String(describing: finalState))")
            return
        }
        #expect(log.endReason == .endedByDriver)
    }
}

struct RecoverIncompleteTripUseCaseTests {
    @Test func `closes a cut-off drive as incomplete`() async throws {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var log = TripLog(startedAt: start, startCoordinate: Coordinate(latitude: 47.6, longitude: -122.3))
        log.append(TripLogEntry(
            timestamp: start.addingTimeInterval(300),
            coordinate: Coordinate(latitude: 47.61, longitude: -122.3),
            event: .muted,
        ))
        let store = MemoryTripLogStore(unfinished: log)

        let recovered = try await RecoverIncompleteTripUseCase(tripLogStore: store)()

        #expect(recovered?.endReason == .incomplete)
        #expect(recovered?.endedAt == start.addingTimeInterval(300))
        #expect(await store.finishedReason == .incomplete)
    }

    @Test func `does nothing when the last drive finished normally`() async throws {
        let recovered = try await RecoverIncompleteTripUseCase(tripLogStore: MemoryTripLogStore())()

        #expect(recovered == nil)
    }
}

/// Plays readings with a short pause after each GPS fix, so the drive loop sees every fix like it would live.
private struct PacedSensorSource: SensorSource {
    let readings: [SensorReading]

    func readings(configuration _: SensorConfiguration) async -> AsyncStream<SensorReading> {
        let readings = readings
        return AsyncStream { continuation in
            let task = Task {
                for reading in readings {
                    continuation.yield(reading)
                    if case .location = reading {
                        try? await Task.sleep(for: .milliseconds(2))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private actor RecordingAlerts: DriveAlerting {
    private(set) var prepared = false
    private(set) var warnings: [DriveWarning] = []

    func prepare() async {
        prepared = true
    }

    func announce(_ warning: DriveWarning) async {
        warnings.append(warning)
    }
}

private actor MemoryTripLogStore: TripLogStore {
    private(set) var appended: [TripLogEntry] = []
    private(set) var finishedReason: TripEndReason?
    private var unfinished: TripLog?

    init(unfinished: TripLog? = nil) {
        self.unfinished = unfinished
    }

    func begin(_ log: TripLog) async throws {
        unfinished = log
    }

    func append(_ entry: TripLogEntry) async throws {
        appended.append(entry)
    }

    func finish(at _: Date, reason: TripEndReason, endCoordinate _: Coordinate?) async throws {
        finishedReason = reason
        unfinished = nil
    }

    func unfinishedLog() async throws -> TripLog? {
        unfinished
    }

    func finishedLogs() async throws -> [TripLog] {
        []
    }

    func saveFinished(_: TripLog) async throws {}
    func deleteFinished(id _: TripLog.ID) async throws {}
}

private actor MemoryTripRepository: TripRepository {
    private var trips: [Trip] = []

    func allTrips() -> [Trip] {
        trips
    }

    func save(_ trip: Trip) {
        trips.append(trip)
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

private struct NoDirections: DirectionsProviding {
    func routes(from _: Coordinate, to _: Place) async throws -> [Route] {
        []
    }
}

private struct NoHotspotService: HotspotService {
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

private struct FixedPreferences: UserPreferences {
    let preferences: AppPreferences

    func load() async -> AppPreferences {
        preferences
    }

    func save(_: AppPreferences) async {}
}
