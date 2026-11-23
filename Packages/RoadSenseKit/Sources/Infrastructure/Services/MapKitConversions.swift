import Application
import Domain
import Foundation
import MapKit
import SensorCore

// MapKit types stop here: everything past this file sees only Domain and Application types.

extension CLLocationCoordinate2D {
    init(_ coordinate: Coordinate) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

extension Coordinate {
    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

extension MKMapItem {
    /// A map item at `coordinate`, for directions requests.
    static func at(_ coordinate: Coordinate) -> MKMapItem {
        MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
    }

    /// The localized "Unknown Location" MapKit puts in `name` when an item has no real name.
    static let placeholderName = MKMapItem.at(Coordinate(latitude: 0, longitude: 0)).name

    /// The item's name, unless it's only MapKit's placeholder.
    var realName: String? {
        name == Self.placeholderName ? nil : name
    }
}

extension Place {
    /// A place from a search result, or `nil` if the result has neither a name nor an address.
    init?(mapItem: MKMapItem) {
        let address = mapItem.address?.shortAddress ?? mapItem.address?.fullAddress
        guard let name = mapItem.realName ?? address, !name.isEmpty else { return nil }
        self.init(
            name: name,
            // Don't repeat the name as the subtitle when the result is just an address.
            subtitle: address == name ? nil : address,
            coordinate: Coordinate(mapItem.location.coordinate),
        )
    }
}

extension Route {
    /// A route from a MapKit polyline.
    /// - Throws: `RouteError` if the polyline has fewer than two distinct points.
    init(polyline: MKPolyline, name: String, expectedTravelTime: TimeInterval) throws(RouteError) {
        let mapPoints = polyline.points()
        let points = (0 ..< polyline.pointCount).map { Coordinate(mapPoints[$0].coordinate) }
        try self.init(name: name, points: points, expectedTravelTime: expectedTravelTime)
    }
}

extension MapServiceError {
    /// The error to report for a MapKit failure, or `nil` when MapKit just means "nothing found".
    init?(mapKitError error: any Error) {
        guard let mapKitError = error as? MKError else {
            self = .unavailable
            return
        }
        switch mapKitError.code {
        case .placemarkNotFound, .directionsNotFound:
            return nil
        case .loadingThrottled:
            self = .throttled
        default:
            self = .unavailable
        }
    }
}
