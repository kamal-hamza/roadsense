import Foundation
import SensorCore

/// Generates realistic sensor readings for a scripted drive, seen from a given phone placement.
public struct SyntheticDrive: Sendable {
    public var segments: [DriveSegment]
    public var orientation: PhoneOrientation
    public var startDate: Date
    public var startCoordinate: Coordinate
    public var startCourse: Double
    public var motionRateHz: Double
    public var locationInterval: TimeInterval
    public var seed: UInt64

    public init(
        segments: [DriveSegment],
        orientation: PhoneOrientation = .mount,
        startDate: Date = Date(timeIntervalSinceReferenceDate: 800_000_000),
        startCoordinate: Coordinate = Coordinate(latitude: 47.6062, longitude: -122.3321),
        startCourse: Double = 0,
        motionRateHz: Double = 50,
        locationInterval: TimeInterval = 1,
        seed: UInt64 = 1,
    ) {
        self.segments = segments
        self.orientation = orientation
        self.startDate = startDate
        self.startCoordinate = startCoordinate
        self.startCourse = startCourse
        self.motionRateHz = motionRateHz
        self.locationInterval = locationInterval
        self.seed = seed
    }

    /// All readings in time order.
    public func readings() -> [SensorReading] {
        var generator = Generator(drive: self)
        for segment in segments {
            generator.run(segment)
        }
        return generator.output
    }
}

/// Car state plus the sensor stream being produced.
private struct Generator {
    let drive: SyntheticDrive
    let timeStep: Double
    var random: SeededRandom
    var orientation: PhoneOrientation
    var elapsed = 0.0
    var nextLocationAt = 0.0
    var speed = 0.0
    var course: Double
    var coordinate: Coordinate
    var lastActivityKind: ActivitySample.Kind?
    var output: [SensorReading] = []

    init(drive: SyntheticDrive) {
        self.drive = drive
        timeStep = 1 / drive.motionRateHz
        random = SeededRandom(seed: drive.seed)
        orientation = drive.orientation
        course = drive.startCourse
        coordinate = drive.startCoordinate
    }

    /// What the car (and the person holding the phone) does during one time step.
    struct Dynamics {
        var longitudinal = 0.0
        var lateral = 0.0
        var vertical = 0.0
        var phoneAcceleration = SIMD3<Double>.zero
        var phoneRotation = SIMD3<Double>.zero
        var isFreeFall = false
    }

    mutating func run(_ segment: DriveSegment) {
        if case let .repositionPhone(newOrientation) = segment {
            orientation = newOrientation
            return
        }
        // Mimic the motion chip: one activity update whenever driving starts or stops.
        emitActivityIfChanged(segment.isParked ? .stationary : .automotive)
        let steps = Int((segment.duration * drive.motionRateHz).rounded())
        for index in 0 ..< steps {
            let localTime = Double(index) * timeStep
            step(with: dynamics(for: segment, at: localTime))
        }
    }

    mutating func dynamics(for segment: DriveSegment, at localTime: Double) -> Dynamics {
        var dynamics = Dynamics()
        switch segment {
        case .parked, .cruise, .repositionPhone:
            break
        case .shakePhone:
            dynamics.phoneAcceleration = random.gaussianVector(standardDeviation: 0.8)
            dynamics.phoneRotation = random.gaussianVector(standardDeviation: 3)
        case .dropPhone:
            // Drop: 0.4 s of free fall, then a short impact spike.
            if localTime < 0.4 {
                dynamics.isFreeFall = true
                dynamics.phoneRotation = random.gaussianVector(standardDeviation: 4)
            } else if localTime < 0.45 {
                dynamics.phoneAcceleration = SIMD3(0, 0, 3)
            }
        case let .accelerate(g, _):
            dynamics.longitudinal = g
        case let .brake(g, _):
            // Stop braking once stopped, or speed would go negative.
            dynamics.longitudinal = speed > 0 ? -g : 0
        case let .turn(lateralG, _, toLeft):
            dynamics.lateral = toLeft ? lateralG : -lateralG
        case let .swerve(lateralG, secondsPerSide):
            dynamics.lateral = localTime < secondsPerSide ? lateralG : -lateralG
        case let .bump(g):
            dynamics.vertical = localTime < 0.06 ? g : 0
        }
        return dynamics
    }

    mutating func step(with dynamics: Dynamics) {
        if elapsed >= nextLocationAt {
            emitLocation()
            nextLocationAt += drive.locationInterval
        }
        // Turn rate needed for this sideways force at the current speed (a = v·ω).
        let yawRate = speed > 0.5 ? dynamics.lateral * standardGravity / speed : 0
        emitMotion(dynamics, yawRate: yawRate)
        integrate(longitudinal: dynamics.longitudinal, yawRate: yawRate)
        elapsed += timeStep
    }

    mutating func integrate(longitudinal: Double, yawRate: Double) {
        speed = max(0, speed + longitudinal * standardGravity * timeStep)
        // Compass course goes clockwise, yaw counterclockwise, hence the minus.
        course = (course - yawRate * timeStep * 180 / .pi).truncatingRemainder(dividingBy: 360)
        if course < 0 {
            course += 360
        }
        let distance = speed * timeStep
        let north = cos(course * .pi / 180) * distance
        let east = sin(course * .pi / 180) * distance
        coordinate = Coordinate(
            // ~111 km per degree of latitude; longitude degrees shrink with cos(latitude).
            latitude: coordinate.latitude + north / 111_320,
            longitude: coordinate.longitude + east / (111_320 * cos(coordinate.latitude * .pi / 180)),
        )
    }

    var timestamp: Date {
        drive.startDate.addingTimeInterval(elapsed)
    }

    mutating func emitMotion(_ dynamics: Dynamics, yawRate: Double) {
        // Express the car-frame physics in the phone's tilted axes, as real sensors would.
        let gravity = orientation.toPhone(SIMD3(0, 0, -1))
        let carAcceleration = SIMD3(dynamics.longitudinal, speed * yawRate / standardGravity, dynamics.vertical)
        var userAcceleration = orientation.toPhone(carAcceleration)
            + dynamics.phoneAcceleration
            + random.gaussianVector(standardDeviation: 0.02)
        // In free fall the accelerometer reads zero, so user acceleration cancels gravity.
        if dynamics.isFreeFall {
            userAcceleration = -gravity
        }
        let rotationRate = orientation.toPhone(SIMD3(0, 0, yawRate))
            + dynamics.phoneRotation
            + random.gaussianVector(standardDeviation: 0.005)
        output.append(.motion(MotionSample(
            timestamp: timestamp,
            gravity: gravity,
            userAcceleration: userAcceleration,
            rotationRate: rotationRate,
        )))
    }

    mutating func emitLocation() {
        let isMoving = speed > 1
        output.append(.location(LocationSample(
            timestamp: timestamp,
            coordinate: coordinate,
            horizontalAccuracy: 5,
            speed: max(0, speed + random.gaussian(standardDeviation: 0.15)),
            speedAccuracy: 0.5,
            course: isMoving ? (course + random.gaussian(standardDeviation: 1) + 360)
                .truncatingRemainder(dividingBy: 360) : nil,
            courseAccuracy: isMoving ? 5 : nil,
        )))
    }

    mutating func emitActivityIfChanged(_ kind: ActivitySample.Kind) {
        guard kind != lastActivityKind else { return }
        lastActivityKind = kind
        output.append(.activity(ActivitySample(timestamp: timestamp, kinds: [kind], confidence: .high)))
    }
}
