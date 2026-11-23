import Application
import Domain
import Foundation
import MapKit
import SensorCore

/// Place search with MapKit's `MKLocalSearch`.
public struct MapKitPlaceSearch: PlaceSearching {
    /// Width and height of the area to prefer results in, in meters.
    public var searchRegionSize = 50000.0

    public init() {}

    public func places(matching query: String, near center: Coordinate) async throws -> [Place] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        // A region biases results toward the driver; it doesn't exclude places outside it.
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(center),
            latitudinalMeters: searchRegionSize,
            longitudinalMeters: searchRegionSize,
        )
        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.compactMap(Place.init(mapItem:))
        } catch {
            guard let mapped = MapServiceError(mapKitError: error) else { return [] }
            throw mapped
        }
    }
}
