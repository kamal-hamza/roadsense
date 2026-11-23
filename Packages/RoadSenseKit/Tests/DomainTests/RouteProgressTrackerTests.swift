import Domain
import Foundation
import SensorCore
import Testing

struct RouteProgressTrackerTests {
    private func time(_ seconds: TimeInterval) -> Date {
        Fixtures.start.addingTimeInterval(seconds)
    }

    @Test func `follows the driver along the route`() throws {
        var tracker = try RouteProgressTracker(route: Fixtures.northRoute())

        let progress = tracker.process(Fixtures.point(420, east: 5), at: time(0))

        #expect(abs(progress.distanceAlongRoute - 420) < 1)
        #expect(!progress.isOffRoute)
    }

    @Test func `off route only after more than 10 seconds over 50 meters away`() throws {
        var tracker = try RouteProgressTracker(route: Fixtures.northRoute())
        _ = tracker.process(Fixtures.point(500), at: time(0))

        let justLeft = tracker.process(Fixtures.point(520, east: 80), at: time(1))
        let tenSeconds = tracker.process(Fixtures.point(540, east: 80), at: time(11))
        let elevenSeconds = tracker.process(Fixtures.point(560, east: 80), at: time(12))

        #expect(!justLeft.isOffRoute)
        #expect(!tenSeconds.isOffRoute)
        #expect(elevenSeconds.isOffRoute)
    }

    @Test func `coming back resets the off-route timer`() throws {
        var tracker = try RouteProgressTracker(route: Fixtures.northRoute())
        _ = tracker.process(Fixtures.point(500, east: 80), at: time(0))
        _ = tracker.process(Fixtures.point(520), at: time(8))

        let progress = tracker.process(Fixtures.point(540, east: 80), at: time(15))

        #expect(!progress.isOffRoute)
    }

    @Test func `does not jump ahead on a route that doubles back`() throws {
        // Out 1 km north, then back south 30 m to the east: the return leg passes close to the outbound one.
        let outbound = stride(from: 0.0, through: 1000, by: 100).map { Fixtures.point($0) }
        let back = stride(from: 1000.0, through: 0, by: -100).map { Fixtures.point($0, east: 30) }
        var tracker = try RouteProgressTracker(
            route: Route(name: "Loop", points: outbound + back, expectedTravelTime: 200),
        )
        _ = tracker.process(Fixtures.point(100), at: time(0))

        // 16 m east of the outbound leg is 14 m from the return leg, but we're still on the way out.
        let progress = tracker.process(Fixtures.point(200, east: 16), at: time(10))

        #expect(abs(progress.distanceAlongRoute - 200) < 1)
    }

    @Test func `reroute starts following the new route`() throws {
        var tracker = try RouteProgressTracker(route: Fixtures.northRoute())
        _ = tracker.process(Fixtures.point(1500), at: time(0))
        let detour = try Route(
            name: "Detour",
            points: [Fixtures.point(0, east: 500), Fixtures.point(1000, east: 500)],
            expectedTravelTime: 60,
        )

        tracker.reroute(to: detour)
        let progress = tracker.process(Fixtures.point(100, east: 500), at: time(1))

        #expect(abs(progress.distanceAlongRoute - 100) < 1)
        #expect(progress.distanceFromRoute < 1)
    }
}
