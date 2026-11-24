import Domain
import Foundation
import SensorCore

// Wire format for `POST /v1/routes/hotspots`. Matches server/crates/api/src/dto.rs.

struct PointDTO: Codable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: Coordinate) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }
}

/// The route to check; the server uses it for this request only and never stores it.
struct RouteHotspotsRequestDTO: Encodable {
    let points: [PointDTO]
}

struct RouteHotspotsResponseDTO: Decodable {
    let hotspots: [RouteHotspotDTO]
}

struct RouteHotspotDTO: Decodable {
    let id: UUID
    let kind: String
    let latitude: Double
    let longitude: Double
    let bearing: Double
    let driverCount: Int
    let distanceAlongRoute: Double
    /// Set for hotspots from the city's collision records; missing or `null` for driver-reported ones.
    let reportedCrashes: Int?

    var routeHotspot: RouteHotspot {
        let hotspot = Hotspot(
            id: id,
            kind: HotspotKind(rawValue: kind) ?? .suddenStop,
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            bearing: Bearing(degrees: bearing),
            driverCount: driverCount,
            reportedCrashes: reportedCrashes,
        )
        return RouteHotspot(hotspot: hotspot, distanceAlongRoute: distanceAlongRoute)
    }
}
