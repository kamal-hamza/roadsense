import Foundation

/// A WGS84 latitude/longitude pair, in degrees.
public struct Coordinate: Hashable, Sendable, Codable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle distance to `other`, in meters (haversine formula).
    public func distance(to other: Coordinate) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLat = lat2 - lat1
        let deltaLon = (other.longitude - longitude) * .pi / 180
        // Haversine: accurate on a sphere even for tiny distances.
        let haversine = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        // min(1, …) guards against rounding pushing asin out of range.
        return 2 * earthRadius * asin(min(1, haversine.squareRoot()))
    }

    /// Linear interpolation toward `other`. Accurate over the few meters between GPS fixes.
    public func interpolated(to other: Coordinate, fraction: Double) -> Coordinate {
        Coordinate(
            latitude: latitude + (other.latitude - latitude) * fraction,
            longitude: longitude + (other.longitude - longitude) * fraction,
        )
    }
}
