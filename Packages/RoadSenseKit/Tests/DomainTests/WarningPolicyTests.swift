import Domain
import Foundation
import SensorCore
import Testing

struct WarningPolicyTests {
    @Test(arguments: [(nil, 150.0), (0, 150), (10, 150), (20, 150), (30, 210), (40, 280), (-5, 150)] as [(
        Double?,
        Double,
    )])
    func `warning distance is the larger of 150 m and 7 seconds`(speed: Double?, expected: Double) {
        #expect(WarningPolicy().warningDistance(speed: speed) == expected)
    }

    @Test func `missing heading trusts the route`() {
        #expect(WarningPolicy().isHeading(nil, alignedWith: Fixtures.hotspot(at: 0)))
    }

    @Test(arguments: [(30.0, true), (45, true), (50, false), (180, false)])
    func `heading must match the hotspot within 45 degrees`(heading: Double, isAligned: Bool) {
        let hotspot = Fixtures.hotspot(at: 0)

        #expect(WarningPolicy().isHeading(Bearing(degrees: heading), alignedWith: hotspot) == isAligned)
    }
}
