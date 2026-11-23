import DriveSimulation
import Foundation
import SensorCore
import SensorRecording

/// Plays a synthetic drive in real time. Used in the iOS Simulator, which has no motion sensors.
public struct SimulatedSensorSource: SensorSource {
    public let segments: [DriveSegment]
    public let orientation: PhoneOrientation
    public let repetitions: Int
    /// Speed in m/s when driving a planned path. 13.4 m/s is about 30 mph.
    public let pathCruiseSpeed: Double

    public init(
        segments: [DriveSegment] = DriveSegment.demo,
        orientation: PhoneOrientation = .cupholder,
        repetitions: Int = 5,
        pathCruiseSpeed: Double = 13.4,
    ) {
        self.segments = segments
        self.orientation = orientation
        self.repetitions = repetitions
        self.pathCruiseSpeed = pathCruiseSpeed
    }

    public func readings(configuration: SensorConfiguration) async -> AsyncStream<SensorReading> {
        TimedReadingPlayer.play(makeDrive(configuration).readings(), speed: 1)
    }

    /// Drives the planned path if there is one, otherwise the scripted demo drive.
    func makeDrive(_ configuration: SensorConfiguration) -> SyntheticDrive {
        let seed = UInt64.random(in: 1 ... UInt64.max)
        let path = configuration.plannedPath
        guard let start = path.first, path.count >= 2 else {
            return SyntheticDrive(
                segments: Array(repeating: segments, count: repetitions).flatMap(\.self),
                orientation: orientation,
                startDate: Date(),
                motionRateHz: configuration.motionRateHz,
                seed: seed,
            )
        }
        return SyntheticDrive(
            // Sit long enough at the end for arrival detection (30 s stopped near the destination).
            segments: [.parked(seconds: 2), .followPath(path, cruiseSpeed: pathCruiseSpeed), .parked(seconds: 40)],
            orientation: orientation,
            startDate: Date(),
            startCoordinate: start,
            startCourse: Self.course(from: start, to: path[1]),
            motionRateHz: configuration.motionRateHz,
            seed: seed,
        )
    }

    /// Compass course from `start` toward `end`, in degrees.
    private static func course(from start: Coordinate, to end: Coordinate) -> Double {
        let north = end.latitude - start.latitude
        let east = (end.longitude - start.longitude) * cos(start.latitude * .pi / 180)
        let degrees = atan2(east, north) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }
}
