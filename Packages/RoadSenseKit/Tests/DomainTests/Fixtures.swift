import Domain
import Foundation
import SensorCore

/// Shared test data: a straight route heading due north, and helpers to build fixes and hotspots on it.
enum Fixtures {
    static let origin = Coordinate(latitude: 47.6, longitude: -122.3)
    static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    static let north = Bearing(degrees: 0)
    static let south = Bearing(degrees: 180)

    /// A point `meters` north of the origin (negative is south), shifted `east` meters sideways.
    static func point(_ meters: Double, east: Double = 0) -> Coordinate {
        let alongRoute = origin.offset(by: meters, toward: meters >= 0 ? north : south)
        guard east != 0 else { return alongRoute }
        return alongRoute.offset(by: abs(east), toward: Bearing(degrees: east > 0 ? 90 : 270))
    }

    /// A 2 km straight route north, with a point every 100 m.
    static func northRoute(length: Double = 2000) throws -> Route {
        let points = stride(from: 0.0, through: length, by: 100).map { point($0) }
        return try Route(name: "Test Rd", points: points, expectedTravelTime: length / 15)
    }

    static func hotspot(
        at meters: Double,
        bearing: Bearing = north,
        kind: HotspotKind = .sharpCurve,
        id: UUID = UUID(),
    ) -> Hotspot {
        Hotspot(id: id, kind: kind, coordinate: point(meters), bearing: bearing, driverCount: 7)
    }

    static func routeHotspot(at meters: Double, bearing: Bearing = north) -> RouteHotspot {
        RouteHotspot(hotspot: hotspot(at: meters, bearing: bearing), distanceAlongRoute: meters)
    }

    static func fix(
        at coordinate: Coordinate,
        time: TimeInterval,
        accuracy: Double = 5,
        speed: Double? = 15,
        course: Double? = 0,
    ) -> LocationSample {
        LocationSample(
            timestamp: start.addingTimeInterval(time),
            coordinate: coordinate,
            horizontalAccuracy: accuracy,
            speed: speed,
            speedAccuracy: 1,
            course: course,
            courseAccuracy: 5,
        )
    }
}
