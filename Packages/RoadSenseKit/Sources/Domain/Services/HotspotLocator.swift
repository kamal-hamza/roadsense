import Foundation

/// Places saved hotspots on a route (within the corridor, facing the driver's way) for the offline fallback.
public struct HotspotLocator: Sendable {
    /// Meters either side of the route a hotspot can be and still count as on it.
    public var corridorWidth = 30.0
    /// Degrees the hotspot's direction may differ from the route's direction there.
    public var headingTolerance = 45.0

    public init() {}

    /// The hotspots that lie on `route` in its direction of travel, sorted by distance along it.
    /// - Complexity: O(*h* × *s*) for *h* hotspots and *s* route segments.
    public func locate(_ hotspots: [Hotspot], along route: Route) -> [RouteHotspot] {
        hotspots
            .compactMap { hotspot -> RouteHotspot? in
                let projection = route.projection(of: hotspot.coordinate)
                guard projection.distanceFromRoute <= corridorWidth,
                      hotspot.bearing.isAligned(with: projection.routeBearing, tolerance: headingTolerance)
                else { return nil }
                return RouteHotspot(hotspot: hotspot, distanceAlongRoute: projection.distanceAlongRoute)
            }
            .sorted { $0.distanceAlongRoute < $1.distanceAlongRoute }
    }
}
