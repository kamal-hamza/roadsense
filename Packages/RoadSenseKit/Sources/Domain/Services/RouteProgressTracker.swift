import Foundation
import SensorCore

/// Follows the driver along a route and notices when they've left it.
public struct RouteProgressTracker: Sendable {
    public struct Configuration: Hashable, Sendable {
        /// Meters from the route that count as off it.
        public var offRouteDistance = 50.0
        /// Seconds the driver must stay off the route before re-routing.
        public var offRouteDuration: TimeInterval = 10
        /// How far ahead of the last match to look first, in meters.
        public var searchAhead = 1000.0

        public init() {}
    }

    public let configuration: Configuration
    public private(set) var route: Route
    private var segmentIndex = 0
    private var offRouteSince: Date?

    public init(route: Route, configuration: Configuration = Configuration()) {
        self.route = route
        self.configuration = configuration
    }

    /// Updates progress with the driver's position at `time`.
    public mutating func process(_ coordinate: Coordinate, at time: Date) -> RouteProgress {
        // Search near the last match first, so a route that doubles back on itself doesn't make us jump ahead.
        var projection = route.projection(of: coordinate, in: nearbySegments())
        // Far from the nearby stretch: maybe they rejoined somewhere else, so try the whole route.
        if projection.distanceFromRoute > configuration.offRouteDistance {
            let anywhere = route.projection(of: coordinate)
            if anywhere.distanceFromRoute < projection.distanceFromRoute {
                projection = anywhere
            }
        }
        segmentIndex = projection.segmentIndex

        let isFar = projection.distanceFromRoute > configuration.offRouteDistance
        offRouteSince = isFar ? (offRouteSince ?? time) : nil
        let isOffRoute = offRouteSince.map { time.timeIntervalSince($0) > configuration.offRouteDuration } ?? false

        return RouteProgress(
            distanceAlongRoute: projection.distanceAlongRoute,
            distanceFromRoute: projection.distanceFromRoute,
            routeBearing: projection.routeBearing,
            isOffRoute: isOffRoute,
        )
    }

    /// Switches to a new route (after re-routing) and starts following it from the beginning.
    public mutating func reroute(to newRoute: Route) {
        route = newRoute
        segmentIndex = 0
        offRouteSince = nil
    }

    /// The segment before the last match through `searchAhead` meters past it.
    private func nearbySegments() -> Range<Int> {
        let segments = route.segments
        let first = max(0, segmentIndex - 1)
        let limit = segments[segmentIndex].distanceFromStart + configuration.searchAhead
        var last = segmentIndex
        while last + 1 < segments.count, segments[last + 1].distanceFromStart <= limit {
            last += 1
        }
        return first ..< last + 1
    }
}
