import Application
import Domain
import Foundation
import SensorCore
import Testing

struct FindRouteHotspotsUseCaseTests {
    private static let origin = Coordinate(latitude: 47.6, longitude: -122.3)
    private static let savedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let now = savedAt.addingTimeInterval(3600)

    private let route: Route
    private let destination: Place
    private let hotspot: RouteHotspot

    init() throws {
        let north = Bearing(degrees: 0)
        let end = Self.origin.offset(by: 2000, toward: north)
        route = try Route(name: "Test Rd", points: [Self.origin, end], expectedTravelTime: 120)
        destination = Place(name: "End", coordinate: end)
        let spot = Hotspot(
            id: UUID(),
            kind: .sharpCurve,
            coordinate: Self.origin.offset(by: 800, toward: north),
            bearing: north,
            driverCount: 6,
        )
        hotspot = RouteHotspot(hotspot: spot, distanceAlongRoute: 800)
    }

    private func makeUseCase(
        _ service: ScriptedHotspotService,
        cache: MemoryHotspotCache = MemoryHotspotCache(),
        sleeps: SleepRecorder = SleepRecorder(),
    ) -> FindRouteHotspotsUseCase {
        FindRouteHotspotsUseCase(
            service: service,
            cache: cache,
            sleep: { await sleeps.record($0) },
            now: { Self.now },
        )
    }

    @Test func `live hotspots are returned and saved for offline use`() async throws {
        let cache = MemoryHotspotCache()
        let findHotspots = makeUseCase(ScriptedHotspotService([.success([hotspot])]), cache: cache)

        let plan = try await findHotspots(destination: destination, route: route)

        #expect(plan.freshness == .live)
        #expect(plan.hotspots == [hotspot])
        let saved = try #require(await cache.saved.first)
        #expect(saved.hotspots == [hotspot.hotspot])
        #expect(saved.savedAt == Self.now)
    }

    @Test func `retries with growing waits, then succeeds`() async throws {
        let service = ScriptedHotspotService([.failure(.unavailable), .failure(.unavailable), .success([hotspot])])
        let sleeps = SleepRecorder()
        let findHotspots = makeUseCase(service, sleeps: sleeps)

        let plan = try await findHotspots(destination: destination, route: route)

        #expect(plan.freshness == .live)
        #expect(await service.callCount == 3)
        #expect(await sleeps.durations == [.seconds(1), .seconds(2)])
    }

    @Test func `gives up after three tries`() async throws {
        let service = ScriptedHotspotService(Array(repeating: .failure(.unavailable), count: 5))
        let findHotspots = makeUseCase(service)

        let plan = try await findHotspots(destination: destination, route: route)

        #expect(await service.callCount == 3)
        #expect(plan.freshness == .unavailable)
        #expect(plan.hotspots.isEmpty)
    }

    @Test func `a rejected request isn't retried`() async throws {
        let service = ScriptedHotspotService([.failure(.rejected), .success([hotspot])])
        let findHotspots = makeUseCase(service)

        let plan = try await findHotspots(destination: destination, route: route)

        #expect(await service.callCount == 1)
        #expect(plan.freshness == .unavailable)
    }

    @Test func `falls back to saved hotspots that cover the route`() async throws {
        let cache = MemoryHotspotCache(saved: [
            CachedHotspotArea(route: route, hotspots: [hotspot.hotspot], savedAt: Self.savedAt),
        ])
        let findHotspots = makeUseCase(ScriptedHotspotService([.failure(.rejected)]), cache: cache)

        let plan = try await findHotspots(destination: destination, route: route)

        #expect(plan.freshness == .cached(savedAt: Self.savedAt))
        #expect(plan.hotspots.map(\.id) == [hotspot.id])
    }

    @Test func `ignores saved areas somewhere else`() async throws {
        let elsewhere = try Route(
            name: "Elsewhere",
            points: [
                Self.origin.offset(by: 5000, toward: Bearing(degrees: 90)),
                Self.origin.offset(by: 7000, toward: Bearing(degrees: 90)),
            ],
            expectedTravelTime: 120,
        )
        let cache = MemoryHotspotCache(saved: [
            CachedHotspotArea(route: elsewhere, hotspots: [hotspot.hotspot], savedAt: Self.savedAt),
        ])
        let findHotspots = makeUseCase(ScriptedHotspotService([.failure(.rejected)]), cache: cache)

        let plan = try await findHotspots(destination: destination, route: route)

        #expect(plan.freshness == .unavailable)
    }

    @Test func `overlapping saved areas are merged without duplicates, dated by the oldest`() async throws {
        let older = Self.savedAt.addingTimeInterval(-86400)
        let cache = MemoryHotspotCache(saved: [
            CachedHotspotArea(route: route, hotspots: [hotspot.hotspot], savedAt: Self.savedAt),
            CachedHotspotArea(route: route, hotspots: [hotspot.hotspot], savedAt: older),
        ])
        let findHotspots = makeUseCase(ScriptedHotspotService([.failure(.rejected)]), cache: cache)

        let plan = try await findHotspots(destination: destination, route: route)

        #expect(plan.hotspots.count == 1)
        #expect(plan.freshness == .cached(savedAt: older))
    }

    @Test func `a cache that can't be written doesn't stop the trip`() async throws {
        let cache = MemoryHotspotCache(failsToSave: true)
        let findHotspots = makeUseCase(ScriptedHotspotService([.success([hotspot])]), cache: cache)

        let plan = try await findHotspots(destination: destination, route: route)

        #expect(plan.freshness == .live)
    }
}

private actor ScriptedHotspotService: HotspotService {
    private var script: [Result<[RouteHotspot], HotspotServiceError>]
    private(set) var callCount = 0

    init(_ script: [Result<[RouteHotspot], HotspotServiceError>]) {
        self.script = script
    }

    func hotspots(along _: Route) async throws -> [RouteHotspot] {
        callCount += 1
        return try script.removeFirst().get()
    }
}

private actor MemoryHotspotCache: HotspotCache {
    private(set) var saved: [CachedHotspotArea]
    private let failsToSave: Bool

    init(saved: [CachedHotspotArea] = [], failsToSave: Bool = false) {
        self.saved = saved
        self.failsToSave = failsToSave
    }

    func save(_ area: CachedHotspotArea) async throws {
        if failsToSave {
            throw CocoaError(.fileWriteNoPermission)
        }
        saved.insert(area, at: 0)
    }

    func areas() async throws -> [CachedHotspotArea] {
        saved
    }
}

private actor SleepRecorder {
    private(set) var durations: [Duration] = []

    func record(_ duration: Duration) {
        durations.append(duration)
    }
}
