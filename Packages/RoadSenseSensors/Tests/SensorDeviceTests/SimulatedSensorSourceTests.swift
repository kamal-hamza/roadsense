import DriveSimulation
import Foundation
import SensorCore
@testable import SensorDevice
import SensorRecording
import Testing

struct SimulatedSensorSourceTests {
    @Test func `drives the planned path when there is one`() {
        let start = Coordinate(latitude: 47.6, longitude: -122.3)
        let end = Coordinate(latitude: 47.605, longitude: -122.3)
        let source = SimulatedSensorSource()

        let readings = source.makeDrive(SensorConfiguration(plannedPath: [start, end])).readings()
        let fixes = readings.compactMap { reading -> LocationSample? in
            if case let .location(fix) = reading {
                fix
            } else {
                nil
            }
        }

        #expect((fixes.first?.coordinate.distance(to: start) ?? .infinity) < 1)
        #expect((fixes.last?.coordinate.distance(to: end) ?? .infinity) < 10)
    }
}
