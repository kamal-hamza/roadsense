import Application
import Domain
import Foundation
@testable import Presentation
import SensorCore
import SensorRecording
import Testing

struct LocationAccessViewModelTests {
    @Test(arguments: [
        (LocationAuthorization.notDetermined, LocationAccessViewModel.State.needsPermission),
        (.denied, .denied),
        (.restricted, .restricted),
        (.authorized, .granted),
    ])
    func `maps the permission to a screen state`(
        authorization: LocationAuthorization,
        expected: LocationAccessViewModel.State,
    ) async {
        let viewModel = LocationAccessViewModel(
            checkAccess: CheckLocationAccessUseCase(locationServices: FakeLocationServices(status: authorization)),
        )

        await viewModel.check()

        #expect(viewModel.state == expected)
    }

    @Test func `asking shows the user's answer`() async {
        let services = FakeLocationServices(status: .notDetermined, answer: .denied)
        let viewModel = LocationAccessViewModel(checkAccess: CheckLocationAccessUseCase(locationServices: services))

        await viewModel.requestAccess()

        #expect(viewModel.state == .denied)
    }
}

struct DestinationSearchViewModelTests {
    private func makeViewModel(
        _ result: Result<[Place], any Error>,
        location: FakeLocationServices = FakeLocationServices(),
    ) -> DestinationSearchViewModel {
        DestinationSearchViewModel(searchPlaces: SearchPlacesUseCase(
            locationServices: location,
            placeSearch: FakePlaceSearch(result: result),
        ))
    }

    @Test func `several matches are listed without choosing one`() async {
        let viewModel = makeViewModel(.success([.pike, .space]))
        viewModel.query = "market"

        await viewModel.search()

        #expect(viewModel.state == .results([.pike, .space]))
        #expect(viewModel.selection == nil)
    }

    @Test func `exactly one match is chosen automatically`() async {
        let viewModel = makeViewModel(.success([.pike]))
        viewModel.query = "pike place"

        await viewModel.search()

        #expect(viewModel.selection == .pike)
    }

    @Test func `no matches says so`() async {
        let viewModel = makeViewModel(.success([]))
        viewModel.query = "pkie plcae"

        await viewModel.search()

        #expect(viewModel.state == .noMatches)
    }

    @Test func `blank query goes back to idle`() async {
        let viewModel = makeViewModel(.success([.pike]))
        viewModel.query = "  "

        await viewModel.search()

        #expect(viewModel.state == .idle)
    }

    @Test(arguments: [
        (MapServiceError.unavailable as any Error, PlanningFailure.mapsUnavailable),
        (MapServiceError.throttled, .throttled),
        (LocationServicesError.unavailable, .locationUnavailable),
        (LocationServicesError.notAuthorized, .locationNotAuthorized),
    ])
    func `failures become a reason the screen can explain`(error: any Error, expected: PlanningFailure) async {
        let viewModel = makeViewModel(.failure(error))
        viewModel.query = "coffee"

        await viewModel.search()

        #expect(viewModel.state == .failed(expected))
    }

    @Test func `tapping a result selects it until the view clears it`() {
        let viewModel = makeViewModel(.success([]))

        viewModel.select(.space)
        let selected = viewModel.selection
        viewModel.clearSelection()

        #expect(selected == .space)
        #expect(viewModel.selection == nil)
    }

    @Test func `submitting bumps the counter that restarts the search`() {
        let viewModel = makeViewModel(.success([]))

        viewModel.submit()
        viewModel.submit()

        #expect(viewModel.submissionCount == 2)
    }
}

struct RouteChoiceViewModelTests {
    private func makeViewModel(_ result: Result<[Route], any Error>) -> RouteChoiceViewModel {
        RouteChoiceViewModel(
            destination: .pike,
            planRoute: PlanRouteUseCase(
                locationServices: FakeLocationServices(),
                directions: FakeDirections(result: result),
            ),
        )
    }

    @Test func `loads routes and picks the best one`() async throws {
        let routes = try [Route.sample(name: "Fast"), Route.sample(name: "Scenic")]
        let viewModel = makeViewModel(.success(routes))

        await viewModel.load()

        #expect(viewModel.state == .loaded(routes))
        #expect(viewModel.selectedRoute?.name == "Fast")
    }

    @Test func `driver can pick another route but not one that doesn't exist`() async throws {
        let viewModel = try makeViewModel(.success([Route.sample(name: "Fast"), Route.sample(name: "Scenic")]))
        await viewModel.load()

        viewModel.select(routeAt: 1)
        viewModel.select(routeAt: 5)

        #expect(viewModel.selectedRoute?.name == "Scenic")
    }

    @Test func `no routes means no driving route`() async {
        let viewModel = makeViewModel(.success([]))

        await viewModel.load()

        #expect(viewModel.state == .noRoute)
        #expect(viewModel.selectedRoute == nil)
    }

    @Test func `map failure is shown`() async {
        let viewModel = makeViewModel(.failure(MapServiceError.unavailable))

        await viewModel.load()

        #expect(viewModel.state == .failed(.mapsUnavailable))
    }
}

private extension Place {
    static let pike = Place(name: "Pike Place Market", coordinate: Coordinate(latitude: 47.6097, longitude: -122.3422))
    static let space = Place(name: "Space Needle", coordinate: Coordinate(latitude: 47.6205, longitude: -122.3493))
}

private extension Route {
    static func sample(name: String) throws -> Route {
        try Route(name: name, points: [FakeLocationServices.here, Place.pike.coordinate], expectedTravelTime: 300)
    }
}

private struct FakeLocationServices: LocationServices {
    static let here = Coordinate(latitude: 47.6062, longitude: -122.3321)

    var status: LocationAuthorization = .authorized
    var answer: LocationAuthorization = .authorized

    func authorization() async -> LocationAuthorization {
        status
    }

    func requestAuthorization() async -> LocationAuthorization {
        answer
    }

    func currentLocation() async throws -> LocationSample {
        LocationSample(
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

private struct FakePlaceSearch: PlaceSearching {
    let result: Result<[Place], any Error>

    func places(matching _: String, near _: Coordinate) async throws -> [Place] {
        try result.get()
    }
}

private struct FakeDirections: DirectionsProviding {
    let result: Result<[Route], any Error>

    func routes(from _: Coordinate, to _: Place) async throws -> [Route] {
        try result.get()
    }
}
