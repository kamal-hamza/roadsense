import Foundation

/// Where the hotspots in a trip plan came from.
public enum HotspotFreshness: Hashable, Sendable, Codable {
    /// Just fetched from the backend.
    case live
    /// Loaded from the on-device copy because the backend couldn't be reached; may be out of date.
    case cached(savedAt: Date)
    /// No hazard data at all; the driver chose to drive without warnings.
    case unavailable
}

/// Everything the drive needs: where to, which way, and what to warn about.
public struct TripPlan: Hashable, Sendable, Codable {
    public let destination: Place
    public let route: Route
    /// Hotspots on the route, in the order the driver reaches them.
    public let hotspots: [RouteHotspot]
    public let freshness: HotspotFreshness

    public init(destination: Place, route: Route, hotspots: [RouteHotspot], freshness: HotspotFreshness) {
        self.destination = destination
        self.route = route
        self.hotspots = hotspots.sorted { $0.distanceAlongRoute < $1.distanceAlongRoute }
        self.freshness = freshness
    }
}
