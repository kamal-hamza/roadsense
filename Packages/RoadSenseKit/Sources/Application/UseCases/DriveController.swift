import Domain
import Foundation
import SensorCore

/// The drive's decision-making, without any I/O: feed it sensor data, get back what to do.
/// See docs/MVP_USE_CASE_1.md §4.3 (activity diagrams 3–5).
struct DriveController {
    struct Configuration: Sendable {
        var gps = GPSSignalMonitor.Configuration()
        var route = RouteProgressTracker.Configuration()
        var warnings = WarningEngine.Configuration()
        var arrival = ArrivalDetector.Configuration()
        /// A hard brake farther than this from the route isn't linked to a hotspot on it.
        var brakeLinkCorridor = 30.0
        /// GPS fixes kept for hard-brake speeds and traces, in seconds.
        var fixHistory: TimeInterval = 15
    }

    /// Something the drive session must do.
    enum Effect: Hashable, Sendable {
        case announce(DriveWarning)
        case log(TripLogEntry)
        /// The driver has been off the route long enough to need a new one from here.
        case needsReroute(from: Coordinate)
        case arrived(at: Date, coordinate: Coordinate)
    }

    private let configuration: Configuration
    private var gps: GPSSignalMonitor
    private var tracker: RouteProgressTracker
    private var engine: WarningEngine
    private var arrival: ArrivalDetector
    private var recentFixes: [LocationSample] = []
    private var activeWarning: DriveWarning?
    private var hasHazardData: Bool
    private var hardBrakes = 0
    private(set) var isMuted = false
    private(set) var update: DriveUpdate

    /// Where the driver was at the latest fix, if any.
    var lastCoordinate: Coordinate? {
        recentFixes.last?.coordinate
    }

    init(plan: TripPlan, configuration: Configuration = Configuration()) {
        self.configuration = configuration
        gps = GPSSignalMonitor(configuration: configuration.gps)
        tracker = RouteProgressTracker(route: plan.route, configuration: configuration.route)
        engine = WarningEngine(hotspots: plan.hotspots, configuration: configuration.warnings)
        arrival = ArrivalDetector(destination: plan.destination.coordinate, configuration: configuration.arrival)
        hasHazardData = plan.freshness != .unavailable
        update = DriveUpdate(
            routeLength: plan.route.length,
            nextHotspot: plan.hotspots.first,
            hasHazardData: hasHazardData,
        )
    }

    /// Handles the latest fix (if it's new) and any newly detected driving events, at sensor time `now`.
    mutating func process(location: LocationSample?, events: [DrivingEvent], at now: Date) -> [Effect] {
        var effects: [Effect] = []
        let newFix = location.flatMap { $0.timestamp != recentFixes.last?.timestamp ? $0 : nil }
        let status: GPSStatus
        if let newFix {
            remember(newFix)
            status = gps.process(newFix, at: now)
        } else {
            status = gps.status(at: now)
        }

        // Warnings pause while the GPS is bad; hotspots passed meanwhile become "missed" once it's back.
        if status == .good, let newFix {
            effects += follow(newFix)
        }
        for event in events where event.kind == .hardBrake {
            effects.append(logHardBrake(event))
        }

        update.gpsStatus = status
        update.speed = newFix?.speed ?? update.speed
        update.nextHotspot = engine.upcoming.first
        update.activeWarning = activeWarning
        update.distanceToWarning = activeWarning.flatMap { warning in
            warning.hotspots.first.map { $0.distanceAlongRoute - update.distanceAlongRoute }
        }
        update.hardBrakes = hardBrakes
        return effects
    }

    /// Mutes or unmutes warnings, returning the log entry for it.
    mutating func setMuted(_ muted: Bool, at time: Date) -> [Effect] {
        guard muted != isMuted else { return [] }
        isMuted = muted
        update.isMuted = muted
        if muted {
            // A muted banner would still distract, so drop it.
            activeWarning = nil
            update.activeWarning = nil
        }
        return [.log(TripLogEntry(timestamp: time, coordinate: nil, event: muted ? .muted : .unmuted))]
    }

    /// Switches to a new route after re-routing. `hasHazardData` is false for a detour with no hotspot data.
    mutating func reroute(to route: Route, hotspots: [RouteHotspot], hasHazardData: Bool) {
        tracker.reroute(to: route)
        engine.reroute(hotspots: hotspots)
        self.hasHazardData = hasHazardData
        update.routeLength = route.length
        update.distanceAlongRoute = 0
        update.hasHazardData = hasHazardData
    }

    private mutating func remember(_ fix: LocationSample) {
        let history = configuration.fixHistory
        recentFixes.append(fix)
        recentFixes.removeAll { fix.timestamp.timeIntervalSince($0.timestamp) > history }
    }

    /// One good fix: track progress, decide warnings and passes, and watch for arrival.
    private mutating func follow(_ fix: LocationSample) -> [Effect] {
        var effects: [Effect] = []
        let progress = tracker.process(fix.coordinate, at: fix.timestamp)
        update.distanceAlongRoute = progress.distanceAlongRoute
        if progress.isOffRoute {
            effects.append(.needsReroute(from: fix.coordinate))
        }

        let position = DrivePosition(
            timestamp: fix.timestamp,
            distanceAlongRoute: progress.distanceAlongRoute,
            speed: fix.speed,
            heading: fix.course.map { Bearing(degrees: $0) },
        )
        for decision in engine.update(position, isMuted: isMuted) {
            switch decision {
            case let .warn(warning):
                effects += handle(warning, at: fix)
            case let .passed(pass):
                effects.append(.log(TripLogEntry(
                    timestamp: pass.timestamp,
                    coordinate: fix.coordinate,
                    event: .hotspotPassed(
                        hotspotID: pass.hotspot.id,
                        outcome: pass.outcome,
                        brakedHard: pass.brakedHard,
                    ),
                )))
                // A warning's hotspots are in route order, so passing the last one means all are behind us.
                if activeWarning?.hotspots.last?.id == pass.hotspot.id {
                    activeWarning = nil
                }
            }
        }

        if arrival.process(fix) {
            effects.append(.arrived(at: fix.timestamp, coordinate: fix.coordinate))
        }
        return effects
    }

    private mutating func handle(_ warning: DriveWarning, at fix: LocationSample) -> [Effect] {
        let ids = warning.hotspots.map(\.id)
        if warning.isSuppressed {
            return [.log(TripLogEntry(
                timestamp: fix.timestamp,
                coordinate: fix.coordinate,
                event: .warningSuppressed(hotspotIDs: ids),
            ))]
        }
        activeWarning = warning
        return [
            .announce(warning),
            .log(TripLogEntry(
                timestamp: fix.timestamp,
                coordinate: fix.coordinate,
                event: .warningShown(hotspotIDs: ids, speed: fix.speed),
            )),
        ]
    }

    /// Logs a hard brake with its speeds, a short GPS trace, and the hotspot it was near (activity diagram 5).
    private mutating func logHardBrake(_ event: DrivingEvent) -> Effect {
        hardBrakes += 1
        var context: HardBrakeContext?
        if let coordinate = event.coordinate {
            let projection = tracker.route.projection(of: coordinate)
            if projection.distanceFromRoute <= configuration.brakeLinkCorridor {
                context = engine.recordHardBrake(atDistanceAlongRoute: projection.distanceAlongRoute)
            }
        }
        // Speed before: the last fix at least 1.5 s before the peak. After: the latest fix past the peak.
        let before = recentFixes.last { event.timestamp.timeIntervalSince($0.timestamp) >= 1.5 }
        let after = recentFixes.last { $0.timestamp > event.timestamp }
        // Up to 5 fixes closest in time to the brake, so the backend can match the road and direction.
        let trace = recentFixes
            .sorted {
                abs($0.timestamp.timeIntervalSince(event.timestamp)) <
                    abs($1.timestamp.timeIntervalSince(event.timestamp))
            }
            .prefix(5)
            .sorted { $0.timestamp < $1.timestamp }
            .map { TracePoint(coordinate: $0.coordinate, course: $0.course) }
        let record = HardBrakeRecord(
            course: event.course,
            speedBefore: before?.speed,
            speedAfter: after?.speed,
            peakDeceleration: event.peakAcceleration,
            nearestHotspotID: context?.hotspot.id,
            wasWarned: context?.warnedAt != nil,
            secondsSinceWarning: context?.warnedAt.map { event.timestamp.timeIntervalSince($0) },
            trace: trace,
        )
        return .log(TripLogEntry(timestamp: event.timestamp, coordinate: event.coordinate, event: .hardBrake(record)))
    }
}
