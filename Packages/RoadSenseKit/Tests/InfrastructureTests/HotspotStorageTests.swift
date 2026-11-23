import Application
import Domain
import Foundation
@testable import Infrastructure
import SensorCore
import Testing

private let origin = Coordinate(latitude: 47.6, longitude: -122.3)
private let north = Bearing(degrees: 0)

private func northRoute(length: Double) throws -> Route {
    try Route(name: "Test Rd", points: [origin, origin.offset(by: length, toward: north)], expectedTravelTime: 100)
}

struct FileHotspotCacheTests {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "File HotspotCache Tests-\(UUID().uuidString)/areas.json")
    }

    private func area(savedAt seconds: TimeInterval) throws -> CachedHotspotArea {
        let hotspot = Hotspot(id: UUID(), kind: .shortMerge, coordinate: origin, bearing: north, driverCount: 5)
        return try CachedHotspotArea(
            route: northRoute(length: 1000),
            hotspots: [hotspot],
            savedAt: Date(timeIntervalSinceReferenceDate: seconds),
        )
    }

    @Test func `starts empty`() async throws {
        let cache = FileHotspotCache(fileURL: temporaryFile())

        #expect(try await cache.areas().isEmpty)
    }

    @Test func `persists areas newest first across instances`() async throws {
        let fileURL = temporaryFile()
        let first = try area(savedAt: 1)
        let second = try area(savedAt: 2)

        try await FileHotspotCache(fileURL: fileURL).save(first)
        try await FileHotspotCache(fileURL: fileURL).save(second)
        let reloaded = try await FileHotspotCache(fileURL: fileURL).areas()

        #expect(reloaded == [second, first])
    }

    @Test func `keeps only the newest areas`() async throws {
        let cache = FileHotspotCache(fileURL: temporaryFile(), maximumAreas: 2)

        for seconds in 1 ... 4 {
            try await cache.save(area(savedAt: TimeInterval(seconds)))
        }

        #expect(try await cache.areas().map(\.savedAt.timeIntervalSinceReferenceDate) == [4, 3])
    }
}

struct DemoHotspotServiceTests {
    private let service = DemoHotspotService(latency: .zero)

    @Test func `places hotspots on the route, facing its direction, in order`() async throws {
        let route = try northRoute(length: 3000)

        let hotspots = try await service.hotspots(along: route)

        let expected = [900.0, 1650, 2400]
        #expect(hotspots.count == expected.count)
        #expect(zip(hotspots, expected).allSatisfy { abs($0.distanceAlongRoute - $1) < 1 })
        #expect(hotspots.allSatisfy { $0.hotspot.bearing.difference(to: north) < 1 })
        #expect(hotspots.allSatisfy { $0.hotspot.driverCount >= 5 })
        #expect(HotspotLocator().locate(hotspots.map(\.hotspot), along: route).count == 3)
    }

    @Test func `the same route gets the same hotspot ids`() async throws {
        let route = try northRoute(length: 3000)

        let first = try await service.hotspots(along: route)
        let second = try await service.hotspots(along: route)

        #expect(first.map(\.id) == second.map(\.id))
        #expect(Set(first.map(\.id)).count == 3)
    }

    @Test func `the opposite direction is a different hotspot`() {
        let northbound = DemoHotspotService.stableID(for: origin, bearing: north)
        let southbound = DemoHotspotService.stableID(for: origin, bearing: Bearing(degrees: 180))

        #expect(northbound != southbound)
    }

    @Test func `short routes have none`() async throws {
        #expect(try await service.hotspots(along: northRoute(length: 400)).isEmpty)
    }

    @Test func `offline mode fails like an unreachable backend`() async throws {
        let offline = DemoHotspotService(isOffline: true, latency: .zero)

        await #expect(throws: HotspotServiceError.unavailable) {
            try await offline.hotspots(along: northRoute(length: 3000))
        }
    }
}
