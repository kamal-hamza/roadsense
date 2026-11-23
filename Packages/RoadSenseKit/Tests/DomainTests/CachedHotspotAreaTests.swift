import Domain
import Foundation
import SensorCore
import Testing

struct CachedHotspotAreaTests {
    private func area(_ route: Route) -> CachedHotspotArea {
        CachedHotspotArea(route: route, hotspots: [Fixtures.hotspot(at: 500)], savedAt: Fixtures.start)
    }

    @Test func `covers the same road, even slightly offset`() throws {
        let cached = try area(Fixtures.northRoute())
        let sameRoad = try Route(
            name: "Same",
            points: stride(from: 0.0, through: 2000, by: 50).map { Fixtures.point($0, east: 20) },
            expectedTravelTime: 100,
        )

        #expect(cached.covers(sameRoad))
    }

    @Test func `covers a shorter trip along part of it`() throws {
        let cached = try area(Fixtures.northRoute())
        let part = try Route(name: "Part", points: [Fixtures.point(400), Fixtures.point(1200)], expectedTravelTime: 60)

        #expect(cached.covers(part))
    }

    @Test func `doesn't cover a route that mostly goes elsewhere`() throws {
        let cached = try area(Fixtures.northRoute())
        // Starts on the cached road, then heads a long way east.
        let detour = try Route(
            name: "Detour",
            points: [Fixtures.point(0), Fixtures.point(300)] + stride(from: 200.0, through: 3000, by: 200)
                .map { Fixtures.point(300, east: $0) },
            expectedTravelTime: 300,
        )

        #expect(!cached.covers(detour))
    }

    @Test func `samples long routes instead of checking every point`() throws {
        let cached = try area(Fixtures.northRoute())
        let dense = try Route(
            name: "Dense",
            points: stride(from: 0.0, through: 2000, by: 1).map { Fixtures.point($0) },
            expectedTravelTime: 100,
        )

        #expect(cached.covers(dense))
    }

    @Test func `round-trips through JSON`() throws {
        let cached = try area(Fixtures.northRoute())

        let decoded = try JSONDecoder().decode(CachedHotspotArea.self, from: JSONEncoder().encode(cached))

        #expect(decoded == cached)
    }
}
