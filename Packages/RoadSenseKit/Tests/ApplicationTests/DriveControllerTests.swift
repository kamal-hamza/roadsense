@testable import Application
import Domain
import Foundation
import SensorCore
import Testing

/// A 2 km road due north with hotspots at 800 m and 1500 m, driven fix by fix.
struct DriveControllerTests {
    private static let origin = Coordinate(latitude: 47.6, longitude: -122.3)
    private static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let north = Bearing(degrees: 0)

    private let plan: TripPlan

    init() throws {
        let route = try Route(
            name: "Test Rd",
            points: stride(from: 0.0, through: 2000, by: 100).map { Self.point($0) },
            expectedTravelTime: 140,
        )
        let hotspots = [800.0, 1500].map { distance in
            RouteHotspot(
                hotspot: Hotspot(
                    id: UUID(),
                    kind: .sharpCurve,
                    coordinate: Self.point(distance),
                    bearing: Self.north,
                    driverCount: 6,
                ),
                distanceAlongRoute: distance,
            )
        }
        plan = TripPlan(
            destination: Place(name: "End", coordinate: Self.point(2000)),
            route: route,
            hotspots: hotspots,
            freshness: .live,
        )
    }

    private static func point(_ meters: Double, east: Double = 0) -> Coordinate {
        let along = origin.offset(by: meters, toward: north)
        return east == 0 ? along : along.offset(by: east, toward: Bearing(degrees: 90))
    }

    private static func fix(
        at coordinate: Coordinate,
        time: TimeInterval,
        speed: Double = 15,
        accuracy: Double = 5,
    ) -> LocationSample {
        LocationSample(
            timestamp: start.addingTimeInterval(time),
            coordinate: coordinate,
            horizontalAccuracy: accuracy,
            speed: speed,
            speedAccuracy: 0.5,
            course: speed > 1 ? 0 : nil,
            courseAccuracy: speed > 1 ? 5 : nil,
        )
    }

    /// Drives the whole road at 15 m/s, one fix a second, then sits at the end; returns every effect.
    private func driveThrough(
        _ controller: inout DriveController,
        fixFor: (Int, Double) -> LocationSample = { second, meters in fix(at: point(meters), time: Double(second)) },
    ) -> [DriveController.Effect] {
        var effects: [DriveController.Effect] = []
        var second = 0
        var meters = 0.0
        while meters < 2000 {
            let current = fixFor(second, meters)
            effects += controller.process(location: current, events: [], at: current.timestamp.addingTimeInterval(0.2))
            second += 1
            meters = min(2000, meters + 15)
        }
        // Parked at the destination long enough to count as arrived.
        for _ in 0 ... 31 {
            let parked = Self.fix(at: Self.point(2000), time: Double(second), speed: 0)
            effects += controller.process(location: parked, events: [], at: parked.timestamp.addingTimeInterval(0.2))
            second += 1
        }
        return effects
    }

    private func passes(_ effects: [DriveController.Effect]) -> [HotspotPassOutcome] {
        effects.compactMap { effect in
            guard case let .log(entry) = effect,
                  case let .hotspotPassed(_, outcome, _) = entry.event else { return nil }
            return outcome
        }
    }

    private func announcements(_ effects: [DriveController.Effect]) -> [DriveWarning] {
        effects.compactMap {
            if case let .announce(warning) = $0 {
                warning
            } else {
                nil
            }
        }
    }

    @Test func `warns before each hotspot with at least 7 seconds to spare, then arrives`() {
        var controller = DriveController(plan: plan)

        let effects = driveThrough(&controller)

        #expect(announcements(effects).count == 2)
        let outcomes = passes(effects)
        #expect(outcomes.count == 2)
        for outcome in outcomes {
            guard case let .warned(seconds) = outcome else {
                Issue.record("Expected a warned pass, got \(outcome)")
                continue
            }
            // 150 m at 15 m/s is 10 s; fixes once a second can make it up to 1 s late.
            #expect(seconds >= 9)
        }
        #expect(effects.contains {
            if case .arrived = $0 {
                true
            } else {
                false
            }
        })
    }

    @Test func `muted drives log suppressed warnings and never speak`() {
        var controller = DriveController(plan: plan)
        let muteEffects = controller.setMuted(true, at: Self.start)

        let effects = driveThrough(&controller)

        #expect(muteEffects.count == 1)
        #expect(announcements(effects).isEmpty)
        #expect(passes(effects) == [.suppressed, .suppressed])
    }

    @Test func `bad GPS around a hotspot means no warning and a missed pass`() {
        var controller = DriveController(plan: plan)

        // From 500 m to 900 m the fixes are 80 m inaccurate, like a tunnel.
        let effects = driveThrough(&controller) { second, meters in
            Self.fix(at: Self.point(meters), time: Double(second), accuracy: (500 ... 900).contains(meters) ? 80 : 5)
        }

        #expect(announcements(effects).count == 1)
        #expect(passes(effects).first == .missed)
    }

    @Test func `asks to re-route after more than 10 seconds off the route`() {
        var controller = DriveController(plan: plan)
        var effects: [DriveController.Effect] = []

        for second in 0 ... 12 {
            let offRoute = Self.fix(at: Self.point(300, east: 120), time: Double(second))
            effects += controller.process(location: offRoute, events: [], at: offRoute.timestamp)
        }

        #expect(effects.contains {
            if case .needsReroute = $0 {
                true
            } else {
                false
            }
        })
    }

    @Test func `a hard brake near a warned hotspot is logged with its context`() throws {
        var controller = DriveController(plan: plan)
        var meters = 0.0
        for second in 0 ... 50 where meters < 760 {
            let current = Self.fix(at: Self.point(meters), time: Double(second))
            _ = controller.process(location: current, events: [], at: current.timestamp)
            meters += 15
        }
        let brake = DrivingEvent(
            kind: .hardBrake,
            timestamp: Self.start.addingTimeInterval(49),
            duration: 0.8,
            peakAcceleration: 0.5,
            speed: 14,
            course: 0,
            coordinate: Self.point(760),
            confidence: 0.9,
        )

        let effects = controller.process(location: nil, events: [brake], at: Self.start.addingTimeInterval(51))

        guard case let .log(entry) = try #require(effects.first), case let .hardBrake(record) = entry.event else {
            Issue.record("Expected a hard-brake log entry, got \(effects)")
            return
        }
        #expect(record.nearestHotspotID == plan.hotspots[0].id)
        #expect(record.wasWarned)
        #expect((record.secondsSinceWarning ?? 0) > 0)
        #expect(record.speedBefore == 15)
        #expect(record.trace.count == 5)
        #expect(controller.update.hardBrakes == 1)
    }

    @Test func `sharp turns are logged only near a hotspot on the route`() throws {
        var controller = DriveController(plan: plan)
        var meters = 0.0
        for second in 0 ... 60 where meters < 820 {
            let current = Self.fix(at: Self.point(meters), time: Double(second))
            _ = controller.process(location: current, events: [], at: current.timestamp)
            meters += 15
        }
        let turn = { (at: Double) in
            DrivingEvent(
                kind: .sharpTurn,
                timestamp: Self.start.addingTimeInterval(54),
                duration: 1.2,
                peakAcceleration: 0.42,
                speed: 14,
                course: 0,
                coordinate: Self.point(at),
                confidence: 0.9,
            )
        }

        let nearHotspot = controller.process(location: nil, events: [turn(810)], at: Self.start.addingTimeInterval(55))
        let farFromAny = controller.process(location: nil, events: [turn(300)], at: Self.start.addingTimeInterval(56))

        guard case let .log(entry) = try #require(nearHotspot.first), case let .sharpTurn(record) = entry.event else {
            Issue.record("Expected a sharp-turn log entry, got \(nearHotspot)")
            return
        }
        #expect(record.peakLateralAcceleration == 0.42)
        #expect(record.trace.count == 5)
        #expect(farFromAny.isEmpty)
    }

    @Test func `the banner shows the active warning until its hotspot is passed`() {
        var controller = DriveController(plan: plan)
        var bannerSeen = false
        var meters = 0.0
        for second in 0 ..< 70 {
            let current = Self.fix(at: Self.point(meters), time: Double(second))
            _ = controller.process(location: current, events: [], at: current.timestamp)
            if controller.update.activeWarning != nil {
                bannerSeen = true
                #expect((controller.update.distanceToWarning ?? -1) >= -30)
            }
            meters += 15
        }

        // At 1050 m: the first hotspot (800 m) is passed and the second (1500 m) isn't due yet.
        #expect(bannerSeen)
        #expect(controller.update.activeWarning == nil)
        #expect(controller.update.nextHotspot?.distanceAlongRoute == 1500)
    }

    @Test func `a detour with no hazard data says so`() throws {
        var controller = DriveController(plan: plan)
        let detour = try Route(
            name: "Detour",
            points: [Self.point(0, east: 500), Self.point(2000, east: 500)],
            expectedTravelTime: 150,
        )

        controller.reroute(to: detour, hotspots: [], hasHazardData: false)

        #expect(controller.update.hasHazardData == false)
        #expect(abs(controller.update.routeLength - 2000) < 1)
    }
}
