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
        if case let .followPath(path, cruiseSpeed) = segment {
            follow(path, cruiseSpeed: cruiseSpeed)
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
        case .parked, .cruise, .repositionPhone, .followPath:
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

    /// Steers along `path` with pure pursuit (aim at a point a little ahead), slowing for corners, then stops at its
    /// end.
    mutating func follow(_ path: [Coordinate], cruiseSpeed: Double) {
        guard path.count >= 2 else { return }
        emitActivityIfChanged(.automotive)
        let geometry = PathGeometry(path)
        var segment = 0
        // Long enough for any real route at walking pace, so a steering bug can't loop forever.
        let maximumSteps = Int((geometry.length / 1 + 120) * drive.motionRateHz)
        for _ in 0 ..< maximumSteps {
            let position = geometry.local(coordinate)
            let progress = geometry.progress(of: position, fromSegment: segment)
            segment = progress.segment
            let remaining = geometry.length - progress.distance
            if remaining < 2, speed < 0.5 {
                break
            }
            var dynamics = Dynamics()
            dynamics.longitudinal = longitudinalG(
                remaining: remaining,
                cruiseSpeed: cruiseSpeed,
                corner: geometry.sharpestTurn(after: progress.distance, within: 120),
            )
            // Aim further ahead at speed, like a driver looking down the road.
            let target = geometry.point(atDistance: progress.distance + max(8, speed * 1.2))
            dynamics.lateral = steeringLateralG(toward: target - position)
            step(with: dynamics)
        }
    }

    /// Speeds up to cruise, slows to a safe speed before sharp corners, and stops at the end of the path.
    func longitudinalG(
        remaining: Double,
        cruiseSpeed: Double,
        corner: (degrees: Double, distanceAway: Double)?,
    ) -> Double {
        let braking = 0.2 * standardGravity
        // Gentle stop: brake once the stopping distance (v²/2a) reaches the end.
        if remaining <= speed * speed / (2 * braking) + 2 {
            return speed > 0 ? -0.2 : 0
        }
        if let corner {
            // Sharper corners need slower speeds; a right angle is taken at about 5 m/s (11 mph).
            let cornerSpeed = max(5, cruiseSpeed * (1 - corner.degrees / 110))
            let slowingDistance = (speed * speed - cornerSpeed * cornerSpeed) / (2 * braking)
            if speed > cornerSpeed, corner.distanceAway <= slowingDistance + 5 {
                return -0.2
            }
            if speed >= cornerSpeed, corner.distanceAway < 15 {
                return 0
            }
        }
        if speed < cruiseSpeed {
            return remaining < 6 ? 0.03 : 0.12
        }
        return 0
    }

    /// Sideways g that turns the car toward `offset` (meters east, north), capped at 0.35 g like a normal driver.
    func steeringLateralG(toward offset: SIMD2<Double>) -> Double {
        guard speed > 0.5 else { return 0 }
        let targetCourse = atan2(offset.x, offset.y) * 180 / .pi
        // Signed heading error in -180...180; positive means the target is to the right.
        var error = (targetCourse - course).truncatingRemainder(dividingBy: 360)
        if error > 180 {
            error -= 360
        }
        if error < -180 {
            error += 360
        }
        // Turning right is clockwise, which is negative yaw; aim to fix the error in under a second.
        let yawRate = -error * .pi / 180 * 1.5
        let lateral = speed * yawRate / standardGravity
        return min(0.35, max(-0.35, lateral))
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
