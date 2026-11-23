import Domain

/// Looks up active hotspots along a route, going the driver's way. Implemented in Infrastructure.
public protocol HotspotService: Sendable {
    /// Hotspots on `route` in its direction of travel, sorted by distance along it. May be empty.
    /// - Throws: `HotspotServiceError`.
    func hotspots(along route: Route) async throws -> [RouteHotspot]
}
