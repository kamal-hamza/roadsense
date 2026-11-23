import Domain
import Foundation
import SensorCore
import Testing

struct WarningEngineTests {
    private func position(
        _ meters: Double,
        time: TimeInterval,
        speed: Double? = 15,
        heading: Bearing? = Fixtures.north,
    ) -> DrivePosition {
        DrivePosition(
            timestamp: Fixtures.start.addingTimeInterval(time),
            distanceAlongRoute: meters,
            speed: speed,
            heading: heading,
        )
    }

    private func warnings(_ decisions: [WarningEngine.Decision]) -> [DriveWarning] {
        decisions.compactMap {
            if case let .warn(warning) = $0 {
                warning
            } else {
                nil
            }
        }
    }

    private func passes(_ decisions: [WarningEngine.Decision]) -> [HotspotPass] {
        decisions.compactMap {
            if case let .passed(pass) = $0 {
                pass
            } else {
                nil
            }
        }
    }

    @Test func `warns once when the hotspot comes within warning distance`() {
        var engine = WarningEngine(hotspots: [Fixtures.routeHotspot(at: 1000)])

        let tooFar = engine.update(position(840, time: 0), isMuted: false)
        let inRange = engine.update(position(860, time: 1), isMuted: false)
        let again = engine.update(position(900, time: 4), isMuted: false)

        #expect(tooFar.isEmpty)
        #expect(warnings(inRange).count == 1)
        #expect(abs((warnings(inRange).first?.distance ?? 0) - 140) < 1e-9)
        #expect(again.isEmpty)
    }

    @Test(arguments: [15.0, 25, 35])
    func `gives at least 7 seconds of warning at speed`(speed: Double) throws {
        var engine = WarningEngine(hotspots: [Fixtures.routeHotspot(at: 2000)])
        var allDecisions: [WarningEngine.Decision] = []

        // Drive at constant speed with one fix per second, like real GPS.
        for second in 0 ..< 200 {
            let meters = Double(second) * speed
            allDecisions += engine.update(position(meters, time: Double(second), speed: speed), isMuted: false)
        }

        let pass = try #require(passes(allDecisions).first)
        guard case let .warned(seconds) = pass.outcome else {
            Issue.record("Expected a warned pass, got \(pass.outcome)")
            return
        }
        // Fixes arrive once a second, so the warning can come up to 1 s late.
        #expect(seconds >= 6)
        #expect(seconds <= 11)
    }

    @Test func `groups hotspots inside the same warning distance`() throws {
        var engine = WarningEngine(hotspots: [
            Fixtures.routeHotspot(at: 1000),
            Fixtures.routeHotspot(at: 1040),
            Fixtures.routeHotspot(at: 1400),
        ])

        let decisions = engine.update(position(900, time: 0), isMuted: false)

        let warning = try #require(warnings(decisions).first)
        #expect(warning.hotspots.map(\.distanceAlongRoute) == [1000, 1040])
        #expect(engine.upcoming.map(\.distanceAlongRoute) == [1400])
    }

    @Test func `skips a hotspot facing the other way`() {
        var engine = WarningEngine(hotspots: [Fixtures.routeHotspot(at: 1000)])

        let decisions = engine.update(position(900, time: 0, heading: Fixtures.south), isMuted: false)

        #expect(decisions.isEmpty)
    }

    @Test func `muted warnings are suppressed and never repeated after unmuting`() {
        var engine = WarningEngine(hotspots: [Fixtures.routeHotspot(at: 1000)])

        let muted = engine.update(position(900, time: 0), isMuted: true)
        let unmuted = engine.update(position(950, time: 3), isMuted: false)
        let passed = engine.update(position(1050, time: 10), isMuted: false)

        #expect(warnings(muted).first?.isSuppressed == true)
        #expect(unmuted.isEmpty)
        #expect(passes(passed).first?.outcome == .suppressed)
    }

    @Test func `a hotspot passed during a GPS gap is missed`() {
        var engine = WarningEngine(hotspots: [Fixtures.routeHotspot(at: 1000)])
        _ = engine.update(position(500, time: 0), isMuted: false)

        // The next usable fix is already past the hotspot.
        let decisions = engine.update(position(1100, time: 40), isMuted: false)

        #expect(passes(decisions).first?.outcome == .missed)
        #expect(warnings(decisions).isEmpty)
    }

    @Test func `pass needs 30 m past the hotspot so jitter doesn't count`() {
        var engine = WarningEngine(hotspots: [Fixtures.routeHotspot(at: 1000)])
        _ = engine.update(position(900, time: 0), isMuted: false)

        let atSpot = engine.update(position(1020, time: 8), isMuted: false)
        let past = engine.update(position(1040, time: 9), isMuted: false)

        #expect(passes(atSpot).isEmpty)
        #expect(passes(past).count == 1)
    }

    @Test func `links a hard brake to the hotspot ahead and reports it on the pass`() {
        var engine = WarningEngine(hotspots: [Fixtures.routeHotspot(at: 1000)])
        _ = engine.update(position(900, time: 0), isMuted: false)

        let context = engine.recordHardBrake(atDistanceAlongRoute: 950)
        let decisions = engine.update(position(1050, time: 8), isMuted: false)

        #expect(context?.warnedAt == Fixtures.start)
        #expect(passes(decisions).first?.brakedHard == true)
    }

    @Test(arguments: [(750.0, false), (820, true), (1025, true), (1040, false)])
    func `hard brake links from 200 m before to 30 m after`(brakeAt: Double, isLinked: Bool) {
        var engine = WarningEngine(hotspots: [Fixtures.routeHotspot(at: 1000)])

        let context = engine.recordHardBrake(atDistanceAlongRoute: brakeAt)

        #expect((context != nil) == isLinked)
    }

    @Test func `reroute keeps hotspots already warned about`() {
        let shared = Fixtures.routeHotspot(at: 1000)
        var engine = WarningEngine(hotspots: [shared])
        _ = engine.update(position(900, time: 0), isMuted: false)

        // The new route reaches the same hotspot at a different distance.
        engine.reroute(hotspots: [RouteHotspot(hotspot: shared.hotspot, distanceAlongRoute: 300)])
        let decisions = engine.update(position(200, time: 5), isMuted: false)

        #expect(warnings(decisions).isEmpty)
    }
}
