import Domain
import Foundation
import SensorCore
import Testing

struct GPSSignalMonitorTests {
    private let now = Fixtures.start.addingTimeInterval(100)

    @Test func `accurate fresh fix is good`() {
        var monitor = GPSSignalMonitor()

        let status = monitor.process(Fixtures.fix(at: Fixtures.origin, time: 100), at: now)

        #expect(status == .good)
        #expect(monitor.lastGoodFix != nil)
    }

    @Test(arguments: [(31.0, 0.0), (5, 4), (-1, 0)])
    func `inaccurate, stale, or invalid fix is not used`(accuracy: Double, age: TimeInterval) {
        var monitor = GPSSignalMonitor()

        let status = monitor.process(Fixtures.fix(at: Fixtures.origin, time: 100 - age, accuracy: accuracy), at: now)

        #expect(status == .degraded)
        #expect(monitor.lastGoodFix == nil)
    }

    @Test func `keeps the last good fix while degraded, then reports lost after 30 seconds`() {
        var monitor = GPSSignalMonitor()
        _ = monitor.process(Fixtures.fix(at: Fixtures.origin, time: 0), at: Fixtures.start)

        let tunnel = monitor.process(
            Fixtures.fix(at: Fixtures.point(100), time: 10, accuracy: 80),
            at: Fixtures.start.addingTimeInterval(10),
        )
        let stillTunnel = monitor.status(at: Fixtures.start.addingTimeInterval(29))
        let lost = monitor.status(at: Fixtures.start.addingTimeInterval(30))

        #expect(tunnel == .degraded)
        #expect(stillTunnel == .degraded)
        #expect(lost == .lost)
        #expect(monitor.lastGoodFix?.coordinate == Fixtures.origin)
    }

    @Test func `never getting a good fix becomes lost after 30 seconds`() {
        var monitor = GPSSignalMonitor()
        _ = monitor.process(Fixtures.fix(at: Fixtures.origin, time: 0, accuracy: 100), at: Fixtures.start)

        #expect(monitor.status(at: Fixtures.start.addingTimeInterval(30)) == .lost)
    }
}
