import Domain
import Foundation
import SensorCore
import Testing

struct HotspotLocatorTests {
    @Test func `keeps hotspots on the route facing the same way, in route order`() throws {
        let route = try Fixtures.northRoute()
        let far = Fixtures.hotspot(at: 1500)
        let near = Fixtures.hotspot(at: 300)
        let oppositeDirection = Fixtures.hotspot(at: 800, bearing: Fixtures.south)
        let offRoad = Hotspot(
            id: UUID(),
            kind: .suddenStop,
            coordinate: Fixtures.point(1000, east: 60),
            bearing: Fixtures.north,
            driverCount: 9,
        )

        let located = HotspotLocator().locate([far, oppositeDirection, offRoad, near], along: route)

        #expect(located.map(\.id) == [near.id, far.id])
        #expect(abs(located[0].distanceAlongRoute - 300) < 1)
    }

    @Test(arguments: [(29.0, true), (31, false)])
    func `corridor is 30 meters`(sideways: Double, isOnRoute: Bool) throws {
        let route = try Fixtures.northRoute()
        let hotspot = Hotspot(
            id: UUID(),
            kind: .shortMerge,
            coordinate: Fixtures.point(500, east: sideways),
            bearing: Fixtures.north,
            driverCount: 5,
        )

        let located = HotspotLocator().locate([hotspot], along: route)

        #expect(located.isEmpty == !isOnRoute)
    }
}
