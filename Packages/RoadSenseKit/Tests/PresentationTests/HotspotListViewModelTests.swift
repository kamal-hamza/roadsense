import Application
import Domain
import Foundation
@testable import Presentation
import SensorCore
import Testing

struct HotspotListViewModelTests {
    private let destination = Place(name: "End", coordinate: Coordinate(latitude: 47.62, longitude: -122.3))
    private let route: Route
    private let hotspot: RouteHotspot

    init() throws {
        let start = Coordinate(latitude: 47.6, longitude: -122.3)
        route = try Route(name: "Test Rd", points: [start, destination.coordinate], expectedTravelTime: 200)
        let spot = Hotspot(
            id: UUID(),
            kind: .shortMerge,
            coordinate: start,
            bearing: Bearing(degrees: 0),
            driverCount: 8,
        )
        hotspot = RouteHotspot(hotspot: spot, distanceAlongRoute: 300)
    }

    private func makeViewModel(
        _ result: Result<[RouteHotspot], HotspotServiceError>,
        saved: [CachedHotspotArea] = [],
    ) -> HotspotListViewModel {
        HotspotListViewModel(
            destination: destination,
            route: route,
            findHotspots: FindRouteHotspotsUseCase(
                service: FixedHotspotService(result: result),
                cache: FixedHotspotCache(areas: saved),
                retryDelays: [],
            ),
        )
    }

    @Test func `live hotspots make the plan ready`() async {
        let viewModel = makeViewModel(.success([hotspot]))

        await viewModel.load()

        guard case let .ready(plan) = viewModel.state else {
            Issue.record("Expected .ready, got \(viewModel.state)")
            return
        }
        #expect(plan.hotspots == [hotspot])
        #expect(plan.freshness == .live)
    }

    @Test func `saved hotspots are used and marked as possibly old`() async {
        let savedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let viewModel = makeViewModel(
            .failure(.unavailable),
            saved: [CachedHotspotArea(route: route, hotspots: [hotspot.hotspot], savedAt: savedAt)],
        )

        await viewModel.load()

        guard case let .ready(plan) = viewModel.state else {
            Issue.record("Expected .ready, got \(viewModel.state)")
            return
        }
        #expect(plan.freshness == .cached(savedAt: savedAt))
    }

    @Test func `no data asks the driver, who can drive without warnings`() async {
        let viewModel = makeViewModel(.failure(.unavailable))

        await viewModel.load()
        let beforeChoice = viewModel.state
        viewModel.driveWithoutWarnings()

        #expect(beforeChoice == .unavailable)
        #expect(viewModel.state == .ready(TripPlan(
            destination: destination,
            route: route,
            hotspots: [],
            freshness: .unavailable,
        )))
    }
}

private struct FixedHotspotService: HotspotService {
    let result: Result<[RouteHotspot], HotspotServiceError>

    func hotspots(along _: Route) async throws -> [RouteHotspot] {
        try result.get()
    }
}

private struct FixedHotspotCache: HotspotCache {
    let areas: [CachedHotspotArea]

    func save(_: CachedHotspotArea) async throws {}

    func areas() async throws -> [CachedHotspotArea] {
        areas
    }
}
