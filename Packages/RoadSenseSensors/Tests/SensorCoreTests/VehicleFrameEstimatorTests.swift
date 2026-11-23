import DriveSimulation
import Foundation
import SensorCore
import Testing

struct VehicleFrameEstimatorTests {
    @Test(arguments: PhoneOrientation.testPlacements)
    func `learns the forward axis in any placement`(orientation: PhoneOrientation) throws {
        var estimator = VehicleFrameEstimator()

        estimator.feed(SyntheticDrive(segments: DriveSegment.warmUp, orientation: orientation).readings())

        #expect(estimator.isFrameReady)
        let forward = try #require(estimator.forward)
        #expect(forward.dot(orientation.forwardInPhoneFrame) > 0.98)
    }

    @Test func `isn't ready before the car changes speed`() {
        var estimator = VehicleFrameEstimator()

        estimator.feed(SyntheticDrive(segments: [.parked(seconds: 10)]).readings())

        #expect(!estimator.isFrameReady)
    }

    @Test func `relearns after the phone is moved`() throws {
        var estimator = VehicleFrameEstimator()
        let speedChanges: [DriveSegment] = [
            .brake(g: 0.10, seconds: 3), .accelerate(g: 0.12, seconds: 5),
            .brake(g: 0.10, seconds: 3), .accelerate(g: 0.12, seconds: 4),
        ]
        let beforeMove = DriveSegment.warmUp + [.repositionPhone(.pocket), .cruise(seconds: 1)]

        estimator.feed(SyntheticDrive(segments: beforeMove, orientation: .mount).readings())
        #expect(!estimator.isFrameReady)

        let moveTime = lastTimestamp(of: beforeMove)
        estimator.feed(SyntheticDrive(
            segments: beforeMove + speedChanges,
            orientation: .mount,
        ).readings().filter { $0.timestamp > moveTime })

        #expect(estimator.isFrameReady)
        let forward = try #require(estimator.forward)
        #expect(forward.dot(PhoneOrientation.pocket.forwardInPhoneFrame) > 0.98)
    }

    @Test func `flags the phone as unsettled while it's handled`() {
        var estimator = VehicleFrameEstimator()
        var settledStates: [Bool] = []

        for reading in SyntheticDrive(segments: [.parked(seconds: 2), .shakePhone(seconds: 3)]).readings() {
            if case let .motion(sample) = reading {
                settledStates.append(estimator.process(sample).isPhoneSettled)
            }
        }

        #expect(settledStates.first == true)
        #expect(settledStates.last == false)
    }

    @Test func `measures turn rate regardless of placement`() {
        for orientation in PhoneOrientation.testPlacements {
            var estimator = VehicleFrameEstimator()
            var yawRates: [Double] = []
            let drive = SyntheticDrive(segments: DriveSegment.warmUp + [.turn(lateralG: 0.4, seconds: 3)])

            for reading in SyntheticDrive(segments: drive.segments, orientation: orientation).readings() {
                switch reading {
                case let .motion(sample): yawRates.append(estimator.process(sample).yawRate)
                case let .location(sample): estimator.process(sample)
                default: break
                }
            }

            // 0.4 g at ~17.7 m/s ≈ 0.22 rad/s to the left.
            #expect(abs((yawRates.last ?? 0) - 0.22) < 0.03, "\(orientation)")
        }
    }

    private func lastTimestamp(of segments: [DriveSegment]) -> Date {
        SyntheticDrive(segments: segments).readings().last?.timestamp ?? .distantPast
    }
}

extension VehicleFrameEstimator {
    mutating func feed(_ readings: [SensorReading]) {
        for reading in readings {
            switch reading {
            case let .motion(sample): _ = process(sample)
            case let .location(sample): process(sample)
            default: break
            }
        }
    }
}
