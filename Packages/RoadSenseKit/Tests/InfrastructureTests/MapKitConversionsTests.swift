import Application
import Domain
import Foundation
@testable import Infrastructure
import MapKit
import SensorCore
import Testing

struct MapKitConversionsTests {
    private let pike = Coordinate(latitude: 47.6097, longitude: -122.3422)

    @Test func `place keeps the name, short address, and coordinate`() throws {
        let item = MKMapItem.at(pike)
        item.name = "Pike Place Market"
        let address = try #require(MKAddress(fullAddress: "85 Pike St, Seattle, WA 98101", shortAddress: "85 Pike St"))
        let named = MKMapItem(location: item.location, address: address)
        named.name = "Pike Place Market"

        let place = try #require(Place(mapItem: named))

        #expect(place.name == "Pike Place Market")
        #expect(place.subtitle == "85 Pike St")
        #expect(abs(place.coordinate.latitude - pike.latitude) < 1e-9)
    }

    @Test func `an address-only result uses the address as the name without repeating it`() throws {
        let address = try #require(MKAddress(fullAddress: "85 Pike St, Seattle", shortAddress: "85 Pike St"))
        let item = MKMapItem(location: MKMapItem.at(pike).location, address: address)

        let place = try #require(Place(mapItem: item))

        #expect(place.name == "85 Pike St")
        #expect(place.subtitle == nil)
    }

    @Test func `route comes from the polyline points`() throws {
        var coordinates = [
            CLLocationCoordinate2D(latitude: 47.60, longitude: -122.33),
            CLLocationCoordinate2D(latitude: 47.61, longitude: -122.33),
            CLLocationCoordinate2D(latitude: 47.61, longitude: -122.32),
        ]
        let polyline = MKPolyline(coordinates: &coordinates, count: coordinates.count)

        let route = try Route(polyline: polyline, name: "Main St", expectedTravelTime: 240)

        #expect(route.points.count == 3)
        #expect(route.name == "Main St")
        #expect(abs((route.points.last?.longitude ?? 0) + 122.32) < 1e-9)
    }

    @Test func `a single-point polyline is rejected`() {
        var coordinates = [CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)]
        let polyline = MKPolyline(coordinates: &coordinates, count: 1)

        #expect(throws: RouteError.tooFewPoints) {
            try Route(polyline: polyline, name: "", expectedTravelTime: 0)
        }
    }

    @Test(arguments: [
        (MKError.Code.placemarkNotFound, nil),
        (.directionsNotFound, nil),
        (.loadingThrottled, .throttled),
        (.serverFailure, .unavailable),
        (.unknown, .unavailable),
    ] as [(MKError.Code, MapServiceError?)])
    func `maps MapKit errors`(code: MKError.Code, expected: MapServiceError?) {
        #expect(MapServiceError(mapKitError: MKError(code)) == expected)
    }

    @Test func `non-MapKit errors count as unavailable`() {
        #expect(MapServiceError(mapKitError: URLError(.notConnectedToInternet)) == .unavailable)
    }
}
