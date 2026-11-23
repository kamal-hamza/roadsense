import Application
import Domain
import Foundation
import SensorCore

/// Made-up hotspots along any route, for demos until the server exists (M6). Never ship it.
public struct DemoHotspotService: HotspotService {
    /// Simulates the backend being unreachable, to try the offline fallback.
    public var isOffline: Bool
    /// Pretend network delay.
    public var latency: Duration

    public init(isOffline: Bool = false, latency: Duration = .milliseconds(600)) {
        self.isOffline = isOffline
        self.latency = latency
    }

    public func hotspots(along route: Route) async throws -> [RouteHotspot] {
        try await Task.sleep(for: latency)
        guard !isOffline else { throw HotspotServiceError.unavailable }
        // Very short routes get none, so "No known hotspots" can be demoed too.
        guard route.length >= 600 else { return [] }

        let kinds: [HotspotKind] = [.sharpCurve, .suddenStop, .shortMerge]
        // A few spots at fixed fractions of the route, so the same route always gets the same hotspots.
        return [0.3, 0.55, 0.8].enumerated().map { index, fraction in
            let distance = route.length * fraction
            let location = route.location(atDistance: distance)
            let hotspot = Hotspot(
                id: Self.stableID(for: location.coordinate, bearing: location.bearing),
                kind: kinds[index % kinds.count],
                coordinate: location.coordinate,
                bearing: location.bearing,
                driverCount: 5 + (index * 4),
            )
            return RouteHotspot(hotspot: hotspot, distanceAlongRoute: distance)
        }
    }

    /// The same id for the same spot and direction (to ~10 m and 10°), so cached copies line up with fresh ones.
    static func stableID(for coordinate: Coordinate, bearing: Bearing) -> UUID {
        // 1e-4 degrees of latitude is about 11 m.
        let lat = Int64((coordinate.latitude * 10000).rounded())
        let lon = Int64((coordinate.longitude * 10000).rounded())
        let direction = Int64((bearing.degrees / 10).rounded()) % 36
        let bytes = withUnsafeBytes(of: lat.bigEndian, Array.init) + withUnsafeBytes(
            of: (lon << 8 | direction).bigEndian,
            Array.init,
        )
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15],
        ))
    }
}
