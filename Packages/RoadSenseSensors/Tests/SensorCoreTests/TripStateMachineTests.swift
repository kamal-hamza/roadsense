import DriveSimulation
import Foundation
import SensorCore
import Testing

struct TripStateMachineTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func `starts when driving and ends after parking`() {
        let drive = SyntheticDrive(
            segments: DriveSegment.warmUp + [.brake(g: 0.12, seconds: 16), .parked(seconds: 200)],
            startDate: start,
        )
        var machine = TripStateMachine()

        let transitions = drive.readings().compactMap { machine.process($0) }

        #expect(transitions.count == 2)
        // Backdated to when the car started moving (after the 3 s parked warm-up).
        #expect(transitions.first == .tripStarted(at: start.addingTimeInterval(3)))
        guard case let .tripEnded(endedAt) = transitions.last else {
            Issue.record("Expected the trip to end")
            return
        }
        #expect(endedAt > start.addingTimeInterval(40))
        #expect(machine.state == .idle)
    }

    @Test func `doesn't start from handling the phone while parked`() {
        let drive = SyntheticDrive(segments: [.parked(seconds: 3), .shakePhone(seconds: 20), .dropPhone])
        var machine = TripStateMachine()

        let transitions = drive.readings().compactMap { machine.process($0) }

        #expect(transitions.isEmpty)
    }

    @Test func `ends sooner once the driver walks away`() {
        var machine = TripStateMachine()
        _ = machine.process(.activity(activity(.automotive, at: 0)))
        for second in 0 ... 15 {
            _ = machine.process(.location(location(speed: 10, at: Double(second))))
        }
        #expect(machine.state == .recording(startedAt: start, lastMovingAt: start.addingTimeInterval(15)))

        _ = machine.process(.activity(activity(.walking, at: 20)))
        let transitions = (16 ... 90).compactMap { machine.process(.location(location(speed: 0, at: Double($0)))) }

        #expect(transitions == [.tripEnded(at: start.addingTimeInterval(15))])
    }

    @Test func `gives up on a candidate that never reaches driving speed`() {
        var machine = TripStateMachine()

        _ = machine.process(.activity(activity(.automotive, at: 0)))
        let transitions = (1 ... 130).compactMap { machine.process(.location(location(speed: 2, at: Double($0)))) }

        #expect(transitions.isEmpty)
        #expect(machine.state == .idle)
    }

    private func activity(_ kind: ActivitySample.Kind, at seconds: Double) -> ActivitySample {
        ActivitySample(timestamp: start.addingTimeInterval(seconds), kinds: [kind], confidence: .high)
    }

    private func location(speed: Double, at seconds: Double) -> LocationSample {
        LocationSample(
            timestamp: start.addingTimeInterval(seconds),
            coordinate: Coordinate(latitude: 47.6, longitude: -122.3),
            horizontalAccuracy: 5,
            speed: speed,
            speedAccuracy: 0.5,
            course: nil,
            courseAccuracy: nil,
        )
    }
}
