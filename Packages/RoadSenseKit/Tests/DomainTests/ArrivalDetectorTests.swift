import Domain
import Foundation
import SensorCore
import Testing

struct ArrivalDetectorTests {
    @Test func `arrives after 30 seconds close and slow`() {
        var detector = ArrivalDetector(destination: Fixtures.point(1000))

        let first = detector.process(Fixtures.fix(at: Fixtures.point(980), time: 0, speed: 0.5))
        let almost = detector.process(Fixtures.fix(at: Fixtures.point(985), time: 29, speed: nil))
        let arrived = detector.process(Fixtures.fix(at: Fixtures.point(990), time: 30, speed: 0))

        #expect(!first)
        #expect(!almost)
        #expect(arrived)
    }

    @Test(arguments: [(60.0, 0.0), (10, 2)])
    func `doesn't arrive when too far or too fast`(metersAway: Double, speed: Double) {
        var detector = ArrivalDetector(destination: Fixtures.point(1000))

        _ = detector.process(Fixtures.fix(at: Fixtures.point(1000 - metersAway), time: 0, speed: speed))
        let arrived = detector.process(Fixtures.fix(at: Fixtures.point(1000 - metersAway), time: 60, speed: speed))

        #expect(!arrived)
    }

    @Test func `driving off resets the timer`() {
        var detector = ArrivalDetector(destination: Fixtures.point(1000))
        _ = detector.process(Fixtures.fix(at: Fixtures.point(990), time: 0, speed: 0))
        _ = detector.process(Fixtures.fix(at: Fixtures.point(990), time: 20, speed: 8))

        let arrived = detector.process(Fixtures.fix(at: Fixtures.point(990), time: 35, speed: 0))

        #expect(!arrived)
    }
}
