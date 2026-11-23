import Application
import Domain
import Foundation
import SensorCore
import SensorRecording
import Testing

struct CheckLocationAccessUseCaseTests {
    @Test(arguments: [LocationAuthorization.notDetermined, .denied, .restricted, .authorized])
    func `reports the current permission`(status: LocationAuthorization) async {
        let checkAccess = CheckLocationAccessUseCase(locationServices: StubLocationServices(status: status))

        #expect(await checkAccess() == status)
    }

    @Test func `request returns the user's answer`() async {
        let services = StubLocationServices(status: .notDetermined, answer: .authorized)
        let checkAccess = CheckLocationAccessUseCase(locationServices: services)

        #expect(await checkAccess.request() == .authorized)
    }
}

struct SearchPlacesUseCaseTests {
    @Test func `searches near the current location with a trimmed query`() async throws {
        let search = RecordingPlaceSearch(results: [.sample])
        let searchPlaces = SearchPlacesUseCase(locationServices: StubLocationServices(), placeSearch: search)

        let places = try await searchPlaces("  Pike Place ")

        #expect(places == [.sample])
        #expect(await search.queries == ["Pike Place"])
        #expect(await search.centers == [StubLocationServices.here])
    }

    @Test(arguments: ["", "   "])
    func `blank query returns nothing without searching`(query: String) async throws {
        let search = RecordingPlaceSearch(results: [.sample])
        let searchPlaces = SearchPlacesUseCase(locationServices: StubLocationServices(), placeSearch: search)

        let places = try await searchPlaces(query)

        #expect(places.isEmpty)
        #expect(await search.queries.isEmpty)
    }

    @Test func `passes on a location failure`() async {
        let searchPlaces = SearchPlacesUseCase(
            locationServices: StubLocationServices(locationError: .notAuthorized),
            placeSearch: RecordingPlaceSearch(results: []),
        )

        await #expect(throws: LocationServicesError.notAuthorized) {
            try await searchPlaces("coffee")
        }
    }
}

struct PlanRouteUseCaseTests {
    @Test func `asks for directions from the current location`() async throws {
        let route = try Route(
            name: "Main St",
            points: [StubLocationServices.here, Place.sample.coordinate],
            expectedTravelTime: 300,
        )
        let directions = StubDirections(result: .success([route]))
        let planRoute = PlanRouteUseCase(locationServices: StubLocationServices(), directions: directions)

        let routes = try await planRoute(to: .sample)

        #expect(routes == [route])
    }

    @Test func `passes on a map service failure`() async {
        let planRoute = PlanRouteUseCase(
            locationServices: StubLocationServices(),
            directions: StubDirections(result: .failure(.unavailable)),
        )

        await #expect(throws: MapServiceError.unavailable) {
            try await planRoute(to: .sample)
        }
    }
}

private extension Place {
    static let sample = Place(
        name: "Pike Place Market",
        subtitle: "85 Pike St",
        coordinate: Coordinate(latitude: 47.6097, longitude: -122.3422),
    )
}

private struct StubLocationServices: LocationServices {
    static let here = Coordinate(latitude: 47.6062, longitude: -122.3321)

    var status: LocationAuthorization = .authorized
    var answer: LocationAuthorization = .authorized
    var locationError: LocationServicesError?

    func authorization() async -> LocationAuthorization {
        status
    }

    func requestAuthorization() async -> LocationAuthorization {
        answer
    }

    func currentLocation() async throws -> LocationSample {
        if let locationError {
            throw locationError
        }
        return LocationSample(
            timestamp: .now,
            coordinate: Self.here,
            horizontalAccuracy: 5,
            speed: nil,
            speedAccuracy: nil,
            course: nil,
            courseAccuracy: nil,
        )
    }
}

private actor RecordingPlaceSearch: PlaceSearching {
    let results: [Place]
    private(set) var queries: [String] = []
    private(set) var centers: [Coordinate] = []

    init(results: [Place]) {
        self.results = results
    }

    func places(matching query: String, near center: Coordinate) async throws -> [Place] {
        queries.append(query)
        centers.append(center)
        return results
    }
}

private struct StubDirections: DirectionsProviding {
    let result: Result<[Route], MapServiceError>

    func routes(from _: Coordinate, to _: Place) async throws -> [Route] {
        try result.get()
    }
}
