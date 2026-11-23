import Foundation

/// Decides, on each position update, which hotspots to warn about and which the driver has passed.
/// See docs/MVP_USE_CASE_1.md §4.2 (activity diagram 4).
public struct WarningEngine: Sendable {
    public struct Configuration: Hashable, Sendable {
        public var policy = WarningPolicy()
        /// Meters past a hotspot before it counts as passed, so GPS jitter right at the spot doesn't matter.
        public var passMargin = 30.0
        /// A hard brake up to this many meters before a hotspot is linked to it.
        public var brakeLinkDistance = 200.0

        public init() {}
    }

    /// Something the drive session should act on.
    public enum Decision: Hashable, Sendable {
        case warn(DriveWarning)
        case passed(HotspotPass)
    }

    private enum HotspotState: Hashable, Sendable {
        case pending
        case warned(at: Date)
        case suppressed
        case passed
    }

    public let configuration: Configuration
    public private(set) var hotspots: [RouteHotspot]
    /// Kept by hotspot id, so a re-route that returns the same hotspot never warns twice.
    private var states: [UUID: HotspotState] = [:]
    private var hardBrakeHotspots: Set<UUID> = []
    /// When the driver actually reached each hotspot; the pass is only reported 30 m later.
    private var reachedAt: [UUID: Date] = [:]
    private var previousPosition: DrivePosition?

    public init(hotspots: [RouteHotspot], configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.hotspots = hotspots.sorted { $0.distanceAlongRoute < $1.distanceAlongRoute }
    }

    /// Hotspots still ahead that haven't been warned about or passed, nearest first.
    public var upcoming: [RouteHotspot] {
        hotspots.filter { state(of: $0) == .pending }
    }

    /// Processes a usable GPS position. Call only when the fix is good; gaps turn into missed passes.
    public mutating func update(_ position: DrivePosition, isMuted: Bool) -> [Decision] {
        recordArrivals(at: position)
        // Passes first: a hotspot driven past during a GPS gap is "missed", not warned late.
        var decisions = recordPasses(at: position).map(Decision.passed)
        if let warning = makeWarning(at: position, isMuted: isMuted) {
            decisions.append(.warn(warning))
        }
        previousPosition = position
        return decisions
    }

    /// Links a hard brake at `distanceAlongRoute` to the nearest hotspot it could be about, if any.
    public mutating func recordHardBrake(atDistanceAlongRoute distance: Double) -> HardBrakeContext? {
        // Braking happens before the spot, so look from the brake point forward (and a little behind).
        let candidates = hotspots.filter { hotspot in
            let ahead = hotspot.distanceAlongRoute - distance
            return ahead >= -configuration.passMargin && ahead <= configuration.brakeLinkDistance
        }
        let nearest = candidates.min { abs($0.distanceAlongRoute - distance) < abs($1.distanceAlongRoute - distance) }
        guard let nearest else { return nil }

        hardBrakeHotspots.insert(nearest.id)
        if case let .warned(at) = state(of: nearest) {
            return HardBrakeContext(hotspot: nearest, warnedAt: at)
        }
        return HardBrakeContext(hotspot: nearest, warnedAt: nil)
    }

    /// Replaces the hotspot list after re-routing. Hotspots already warned about or passed stay that way.
    public mutating func reroute(hotspots newHotspots: [RouteHotspot]) {
        hotspots = newHotspots.sorted { $0.distanceAlongRoute < $1.distanceAlongRoute }
        // Distances along the new route aren't comparable with the old one.
        previousPosition = nil
        reachedAt = reachedAt.filter { id, _ in states[id] == .passed }
    }

    private func state(of hotspot: RouteHotspot) -> HotspotState {
        states[hotspot.id] ?? .pending
    }

    private mutating func recordPasses(at position: DrivePosition) -> [HotspotPass] {
        var passes: [HotspotPass] = []
        for hotspot in hotspots where state(of: hotspot) != .passed {
            guard position.distanceAlongRoute > hotspot.distanceAlongRoute + configuration.passMargin else {
                // Sorted by distance, so nothing further along can be passed yet.
                break
            }
            let reachedAt = reachedAt[hotspot.id] ?? position.timestamp
            let outcome: HotspotPassOutcome = switch state(of: hotspot) {
            case let .warned(at): .warned(secondsOfWarning: reachedAt.timeIntervalSince(at))
            case .suppressed: .suppressed
            case .pending, .passed: .missed
            }
            passes.append(HotspotPass(
                hotspot: hotspot,
                outcome: outcome,
                brakedHard: hardBrakeHotspots.contains(hotspot.id),
                timestamp: reachedAt,
            ))
            states[hotspot.id] = .passed
        }
        return passes
    }

    private mutating func recordArrivals(at position: DrivePosition) {
        for hotspot in hotspots where reachedAt[hotspot.id] == nil {
            guard position.distanceAlongRoute >= hotspot.distanceAlongRoute else { break }
            reachedAt[hotspot.id] = estimatedTime(reaching: hotspot.distanceAlongRoute, now: position)
        }
    }

    private mutating func makeWarning(at position: DrivePosition, isMuted: Bool) -> DriveWarning? {
        let policy = configuration.policy
        let warningDistance = policy.warningDistance(speed: position.speed)
        // Every pending hotspot ahead that's close enough and faces the driver's way gets grouped together.
        let due = hotspots.filter { hotspot in
            let ahead = hotspot.distanceAlongRoute - position.distanceAlongRoute
            return state(of: hotspot) == .pending
                && ahead >= 0
                && ahead <= warningDistance
                && policy.isHeading(position.heading, alignedWith: hotspot.hotspot)
        }
        guard let nearest = due.first else { return nil }

        // Mark them now so they're never repeated this trip, even if the driver unmutes later.
        for hotspot in due {
            states[hotspot.id] = isMuted ? .suppressed : .warned(at: position.timestamp)
        }
        return DriveWarning(
            hotspots: due,
            distance: nearest.distanceAlongRoute - position.distanceAlongRoute,
            speed: position.speed,
            isSuppressed: isMuted,
            timestamp: position.timestamp,
        )
    }

    /// Interpolates between the last two updates to estimate when the driver was at `distance`.
    private func estimatedTime(reaching distance: Double, now current: DrivePosition) -> Date {
        guard let previous = previousPosition,
              previous.distanceAlongRoute < distance,
              current.distanceAlongRoute > previous.distanceAlongRoute
        else { return current.timestamp }
        let fraction = (distance - previous.distanceAlongRoute)
            / (current.distanceAlongRoute - previous.distanceAlongRoute)
        let interval = current.timestamp.timeIntervalSince(previous.timestamp)
        return previous.timestamp.addingTimeInterval(fraction * interval)
    }
}
