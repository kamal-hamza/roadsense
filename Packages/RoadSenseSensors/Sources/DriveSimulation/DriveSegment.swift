import Foundation

/// One phase of a synthetic drive.
public enum DriveSegment: Sendable {
    case parked(seconds: Double)
    /// Parked while someone shakes and turns the phone.
    case shakePhone(seconds: Double)
    /// Parked; the phone falls and hits the floor.
    case dropPhone
    case accelerate(g: Double, seconds: Double)
    case cruise(seconds: Double)
    case brake(g: Double, seconds: Double)
    case turn(lateralG: Double, seconds: Double, toLeft: Bool = true)
    /// Sideways one way, then the other, ending in the same direction.
    case swerve(lateralG: Double, secondsPerSide: Double)
    /// A short vertical jolt (pothole, speed bump).
    case bump(g: Double)
    /// Instantly re-seats the phone in a new position.
    case repositionPhone(PhoneOrientation)

    var duration: Double {
        switch self {
        case let .parked(seconds), let .shakePhone(seconds), let .cruise(seconds): seconds
        // // Falling, hitting the floor, and settling takes about 1.5 s.
        case .dropPhone: 1.5
        case let .accelerate(_, seconds), let .brake(_, seconds), let .turn(_, seconds, _): seconds
        case let .swerve(_, secondsPerSide): secondsPerSide * 2
        case .bump: 0.5
        case .repositionPhone: 0
        }
    }

    var isParked: Bool {
        switch self {
        case .parked, .shakePhone, .dropPhone: true
        default: false
        }
    }
}

public extension DriveSegment {
    /// Accelerates and brakes gently so the frame estimator learns "forward". Ends near 17.7 m/s.
    static let warmUp: [DriveSegment] = [
        .parked(seconds: 3),
        .accelerate(g: 0.15, seconds: 10),
        .cruise(seconds: 4),
        .brake(g: 0.10, seconds: 3),
        .accelerate(g: 0.12, seconds: 5),
        .cruise(seconds: 4),
    ]

    /// A drive with one of every event, for the simulator's demo sensor source.
    static let demo: [DriveSegment] = warmUp + [
        .cruise(seconds: 5),
        // // Each event below is followed by a cruise so the detector can settle and confirm it.
        .brake(g: 0.45, seconds: 1.5),
        .cruise(seconds: 3),
        .accelerate(g: 0.15, seconds: 5),
        .cruise(seconds: 4),
        .turn(lateralG: 0.4, seconds: 3),
        .cruise(seconds: 5),
        .swerve(lateralG: 0.3, secondsPerSide: 0.8),
        .cruise(seconds: 5),
        .bump(g: 0.8),
        .cruise(seconds: 5),
        .accelerate(g: 0.32, seconds: 2),
        .cruise(seconds: 4),
        // // Slow to a stop and sit, so the trip state machine sees the drive end.
        .brake(g: 0.12, seconds: 18),
        .parked(seconds: 10),
    ]
}
