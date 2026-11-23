import Foundation
import SensorCore

/// Small-scale geometry on top of `Coordinate`. Accurate over the tens to hundreds of meters routes work at.
public extension Coordinate {
    /// Initial great-circle bearing from this coordinate toward `other`.
    func bearing(to other: Coordinate) -> Bearing {
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLon = (other.longitude - longitude) * .pi / 180
        // Standard forward-azimuth formula; atan2 gives -180...180, Bearing wraps it.
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        return Bearing(degrees: atan2(y, x) * 180 / .pi)
    }

    /// The coordinate `distance` meters away along `bearing`.
    func offset(by distance: Double, toward bearing: Bearing) -> Coordinate {
        let angular = distance / Self.earthRadius
        let heading = bearing.degrees * .pi / 180
        let lat1 = latitude * .pi / 180
        let lon1 = longitude * .pi / 180
        // Destination-point formula on a sphere.
        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(heading))
        let lon2 = lon1 + atan2(sin(heading) * sin(angular) * cos(lat1), cos(angular) - sin(lat1) * sin(lat2))
        return Coordinate(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    /// Mean Earth radius in meters, the same value `Coordinate.distance(to:)` uses.
    internal static let earthRadius = 6_371_000.0

    /// This coordinate in meters east (`x`) and north (`y`) of `origin`, on a flat local map.
    internal func localOffset(from origin: Coordinate) -> (x: Double, y: Double) {
        let metersPerDegree = Self.earthRadius * .pi / 180
        // Equirectangular projection: fine within a few km, and much cheaper than great circles.
        let x = (longitude - origin.longitude) * metersPerDegree * cos(origin.latitude * .pi / 180)
        let y = (latitude - origin.latitude) * metersPerDegree
        return (x, y)
    }
}
