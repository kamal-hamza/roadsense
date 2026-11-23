import Foundation
import SensorCore
import Testing

struct SensorBasicsTests {
    @Test func `measures great-circle distance`() {
        let seattle = Coordinate(latitude: 47.6062, longitude: -122.3321)
        let portland = Coordinate(latitude: 45.5152, longitude: -122.6784)

        #expect(abs(seattle.distance(to: portland) - 233_500) < 2000)
    }

    @Test(arguments: [(350.0, 10.0, 20.0), (10.0, 350.0, -20.0), (90.0, 270.0, 180.0), (0.0, 0.0, 0.0)])
    func `computes signed course differences`(from: Double, to: Double, expected: Double) {
        #expect(abs(courseDifference(from: from, to: to) - expected) < 1e-9)
    }

    @Test func `odometer skips inaccurate and stationary fixes`() {
        var odometer = TripOdometer()
        let origin = Coordinate(latitude: 47.6, longitude: -122.3)
        let north = Coordinate(latitude: 47.6009, longitude: -122.3)

        odometer.add(fix(origin, speed: 10, accuracy: 5, at: 0))
        odometer.add(fix(north, speed: 10, accuracy: 5, at: 10))
        let afterOneLeg = odometer.meters
        odometer.add(fix(origin, speed: 10, accuracy: 200, at: 20))
        odometer.add(fix(north, speed: 0.2, accuracy: 5, at: 30))

        #expect(abs(afterOneLeg - origin.distance(to: north)) < 0.001)
        #expect(odometer.meters == afterOneLeg)
    }

    @Test func `sensor readings round-trip through JSON`() throws {
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let readings: [SensorReading] = [
            .motion(MotionSample(
                timestamp: date,
                gravity: SIMD3(0, 0, -1),
                userAcceleration: SIMD3(0.1, 0.2, 0.3),
                rotationRate: SIMD3(0, 0, 0.5),
            )),
            .location(fix(Coordinate(latitude: 1, longitude: 2), speed: nil, accuracy: 5, at: 0)),
            .activity(ActivitySample(timestamp: date, kinds: [.automotive, .stationary], confidence: .medium)),
            .locationStatus(LocationStatusUpdate(timestamp: date, status: .denied)),
        ]

        let decoded = try JSONDecoder().decode([SensorReading].self, from: JSONEncoder().encode(readings))

        #expect(decoded == readings)
    }

    private func fix(_ coordinate: Coordinate, speed: Double?, accuracy: Double, at seconds: Double) -> LocationSample {
        LocationSample(
            timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds),
            coordinate: coordinate,
            horizontalAccuracy: accuracy,
            speed: speed,
            speedAccuracy: speed == nil ? nil : 0.5,
            course: nil,
            courseAccuracy: nil,
        )
    }
}
