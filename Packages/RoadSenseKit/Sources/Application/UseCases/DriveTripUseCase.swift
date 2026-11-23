import Domain
import Foundation
import SensorCore
import SensorRecording

/// Runs a drive: records sensors, warns before hotspots, logs everything, re-routes, and ends the trip.
/// The decisions live in `DriveController`; this actor does the I/O around it.
public actor DriveTripUseCase {
    public enum DriveError: Error, Equatable, Sendable {
        case alreadyDriving
    }

    private struct Session {
        var controller: DriveController
        var log: TripLog
        var plan: TripPlan
        var eventsSeen = 0
        var lastRerouteAttempt: Date?
        var rerouteTask: Task<Void, Never>?
        var loopTask: Task<Void, Never>?
        var prepareTask: Task<Void, Never>?
        let continuation: AsyncStream<DriveState>.Continuation
    }

    /// Seconds between re-route attempts, so a driver parked off the route doesn't trigger constant lookups.
    private static let rerouteInterval: TimeInterval = 20

    private let recordTrip: RecordTripUseCase
    private let tripLogStore: any TripLogStore
    private let alerting: any DriveAlerting
    private let directions: any DirectionsProviding
    private let findHotspots: FindRouteHotspotsUseCase
    private let configuration: DriveController.Configuration
    private var session: Session?

    public init(
        recordTrip: RecordTripUseCase,
        tripLogStore: any TripLogStore,
        alerting: any DriveAlerting,
        directions: any DirectionsProviding,
        findHotspots: FindRouteHotspotsUseCase,
    ) {
        self.recordTrip = recordTrip
        self.tripLogStore = tripLogStore
        self.alerting = alerting
        self.directions = directions
        self.findHotspots = findHotspots
        configuration = DriveController.Configuration()
    }

    /// The use case's hard-brake rule: at least 0.4 g for at least 0.5 s (stricter than the detector's default).
    static var detection: DetectionPipeline.Configuration {
        var detection = DetectionPipeline.Configuration()
        detection.hardBrakeThreshold = 0.4
        detection.hardBrakeMinimumDuration = 0.5
        return detection
    }

    /// Starts the drive and returns its state as it changes. The stream ends after `.ended`.
    public func start(_ plan: TripPlan) async throws -> AsyncStream<DriveState> {
        guard session == nil else { throw DriveError.alreadyDriving }

        let (states, continuation) = AsyncStream.makeStream(of: DriveState.self, bufferingPolicy: .bufferingNewest(8))
        // The route starts where the driver was when planning, which is close enough for privacy trimming.
        let log = TripLog(startedAt: Date(), startCoordinate: plan.route.points.first)
        session = Session(
            controller: DriveController(plan: plan, configuration: configuration),
            log: log,
            plan: plan,
            continuation: continuation,
        )
        try await tripLogStore.begin(log)
        // Ask for alert permissions alongside the drive, not before it: sensors and speech don't depend on the answer.
        let alerting = alerting
        session?.prepareTask = Task { await alerting.prepare() }

        let options = SensorRecorder.Options(
            sensors: SensorConfiguration(plannedPath: plan.route.points),
            detection: Self.detection,
        )
        let snapshots = try await recordTrip.start(options: options)
        continuation.yield(.driving(DriveUpdate(
            routeLength: plan.route.length,
            nextHotspot: plan.hotspots.first,
            hasHazardData: plan.freshness != .unavailable,
        )))
        session?.loopTask = Task {
            for await snapshot in snapshots {
                await self.handle(snapshot)
            }
            // The sensors ran out without the driver ending the trip (e.g. a replayed log finished).
            await self.finish(reason: .endedByDriver, at: Date(), coordinate: nil)
        }
        return states
    }

    /// Mutes or unmutes warnings for the rest of the drive.
    public func setMuted(_ muted: Bool) async {
        guard var current = session else { return }
        let effects = current.controller.setMuted(muted, at: Date())
        session = current
        await perform(effects)
        publish()
    }

    /// Ends the drive early, at the driver's request.
    public func end() async {
        await finish(reason: .endedByDriver, at: Date(), coordinate: session?.controller.lastCoordinate)
    }

    private func handle(_ snapshot: RecordingSnapshot) async {
        guard var current = session else { return }
        let newEvents = Array(snapshot.events.dropFirst(current.eventsSeen))
        current.eventsSeen = snapshot.events.count
        let effects = current.controller.process(location: snapshot.location, events: newEvents, at: snapshot.timestamp)
        session = current
        await perform(effects)
        publish()
    }

    private func perform(_ effects: [DriveController.Effect]) async {
        for effect in effects {
            switch effect {
            case let .announce(warning):
                await alerting.announce(warning)
            case let .log(entry):
                session?.log.append(entry)
                // The in-memory log still has it; only crash recovery would miss this entry.
                try? await tripLogStore.append(entry)
            case let .needsReroute(coordinate):
                startReroute(from: coordinate)
            case let .arrived(time, coordinate):
                await finish(reason: .arrived, at: time, coordinate: coordinate)
            }
        }
    }

    private func publish() {
        guard let session else { return }
        session.continuation.yield(.driving(session.controller.update))
    }

    /// Gets a new route from here and its hotspots (live, or saved if offline), without blocking the drive.
    private func startReroute(from coordinate: Coordinate) {
        guard var current = session, current.rerouteTask == nil else { return }
        let now = Date()
        if let last = current.lastRerouteAttempt, now.timeIntervalSince(last) < Self.rerouteInterval {
            return
        }
        current.lastRerouteAttempt = now
        let destination = current.plan.destination
        current.rerouteTask = Task {
            let newPlan = await self.planDetour(from: coordinate, to: destination)
            self.applyReroute(newPlan)
        }
        session = current
    }

    private func planDetour(from coordinate: Coordinate, to destination: Place) async -> TripPlan? {
        guard let routes = try? await directions.routes(from: coordinate, to: destination), let route = routes.first
        else { return nil }
        return try? await findHotspots(destination: destination, route: route)
    }

    private func applyReroute(_ newPlan: TripPlan?) {
        guard var current = session else { return }
        current.rerouteTask = nil
        // No new route (offline maps, or no road): keep following the old one and try again later.
        if let newPlan {
            current.plan = newPlan
            current.controller.reroute(
                to: newPlan.route,
                hotspots: newPlan.hotspots,
                hasHazardData: newPlan.freshness != .unavailable,
            )
        }
        session = current
        publish()
    }

    private func finish(reason: TripEndReason, at time: Date, coordinate: Coordinate?) async {
        // Take the session first so a second finish (e.g. arrival racing End Trip) does nothing.
        guard var finished = session else { return }
        session = nil
        finished.rerouteTask?.cancel()
        finished.prepareTask?.cancel()

        let endCoordinate = coordinate ?? finished.controller.lastCoordinate
        // Sensor time can lag the wall clock slightly; never end before the start.
        let endedAt = max(time, finished.log.startedAt)
        try? finished.log.finish(at: endedAt, reason: reason, endCoordinate: endCoordinate)
        try? await tripLogStore.finish(at: endedAt, reason: reason, endCoordinate: finished.log.endCoordinate)
        // Also save it as a Trip so it shows in the Trips tab.
        _ = try? await recordTrip.stop(name: finished.plan.destination.name)

        finished.continuation.yield(.ended(finished.log))
        finished.continuation.finish()
    }
}
