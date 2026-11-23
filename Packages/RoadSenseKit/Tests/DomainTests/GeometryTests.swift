import Domain
import Foundation
import SensorCore
import Testing

struct BearingTests {
    @Test(arguments: [(370.0, 10.0), (-10, 350), (360, 0), (720, 0), (-720, 0), (45, 45)])
    func `wraps into 0 to 360`(input: Double, expected: Double) {
        #expect(abs(Bearing(degrees: input).degrees - expected) < 1e-9)
    }

    @Test(arguments: [(350.0, 10.0, 20.0), (0, 180, 180), (90, 270, 180), (10, 10, 0), (359, 1, 2)])
    func `difference takes the short way round`(from: Double, to: Double, expected: Double) {
        #expect(abs(Bearing(degrees: from).difference(to: Bearing(degrees: to)) - expected) < 1e-9)
    }

    @Test(arguments: [(44.0, true), (45, true), (46, false), (-44, true), (-46, false)])
    func `alignment tolerance is inclusive`(offset: Double, isAligned: Bool) {
        #expect(Fixtures.north.isAligned(with: Bearing(degrees: offset), tolerance: 45) == isAligned)
    }

    @Test func `decodes and wraps through JSON`() throws {
        let decoded = try JSONDecoder().decode(Bearing.self, from: Data("400".utf8))

        #expect(abs(decoded.degrees - 40) < 1e-9)
    }
}

struct CoordinateGeometryTests {
    @Test(arguments: [0.0, 45, 90, 180, 270])
    func `offset then bearing round-trips`(degrees: Double) {
        let target = Fixtures.origin.offset(by: 500, toward: Bearing(degrees: degrees))

        #expect(abs(Fixtures.origin.distance(to: target) - 500) < 0.5)
        #expect(Fixtures.origin.bearing(to: target).difference(to: Bearing(degrees: degrees)) < 0.1)
    }
}

struct RouteTests {
    @Test func `measures length and segment bearings`() throws {
        let route = try Fixtures.northRoute()

        #expect(abs(route.length - 2000) < 1)
        #expect(route.segments.count == 20)
        #expect(route.segments.allSatisfy { $0.bearing.difference(to: Fixtures.north) < 0.1 })
    }

    @Test func `drops repeated points`() throws {
        let route = try Route(
            name: "R",
            points: [Fixtures.point(0), Fixtures.point(0), Fixtures.point(100), Fixtures.point(100)],
            expectedTravelTime: 10,
        )

        #expect(route.points.count == 2)
    }

    @Test(arguments: [[Coordinate](), [Fixtures.origin], [Fixtures.origin, Fixtures.origin]])
    func `rejects fewer than two distinct points`(points: [Coordinate]) {
        #expect(throws: RouteError.tooFewPoints) {
            try Route(name: "R", points: points, expectedTravelTime: 0)
        }
    }

    @Test func `rejects negative travel time`() {
        #expect(throws: RouteError.negativeTravelTime) {
            try Route(name: "R", points: [Fixtures.point(0), Fixtures.point(100)], expectedTravelTime: -1)
        }
    }

    @Test func `projects a point beside the route`() throws {
        let route = try Fixtures.northRoute()

        let projection = route.projection(of: Fixtures.point(750, east: 20))

        #expect(abs(projection.distanceAlongRoute - 750) < 1)
        #expect(abs(projection.distanceFromRoute - 20) < 1)
        #expect(projection.segmentIndex == 7)
    }

    @Test(arguments: [(0.0, 0.0), (750, 750), (2000, 2000), (-50, 0), (2500, 2000)])
    func `finds the spot at a distance along the route`(distance: Double, expected: Double) throws {
        let route = try Fixtures.northRoute()

        let location = route.location(atDistance: distance)

        #expect(location.coordinate.distance(to: Fixtures.point(expected)) < 1)
        #expect(location.bearing.difference(to: Fixtures.north) < 0.1)
    }

    @Test func `direction follows the segment at that distance`() throws {
        let route = try Route(
            name: "L",
            points: [Fixtures.point(0), Fixtures.point(500), Fixtures.point(500, east: 500)],
            expectedTravelTime: 60,
        )

        let location = route.location(atDistance: 700)

        #expect(location.bearing.difference(to: Bearing(degrees: 90)) < 1)
        #expect(location.coordinate.distance(to: Fixtures.point(500, east: 200)) < 1)
    }

    @Test func `round-trips through JSON`() throws {
        let route = try Fixtures.northRoute()

        let decoded = try JSONDecoder().decode(Route.self, from: JSONEncoder().encode(route))

        #expect(decoded == route)
    }
}
