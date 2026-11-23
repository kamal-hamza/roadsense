import Foundation

/// A motion sample re-expressed in the car's axes, independent of where the phone sits.
public struct VehicleMotion: Hashable, Sendable {
    public let timestamp: Date
    /// Forward acceleration in g (+ = speeding up). `nil` until the forward axis is learned.
    public let longitudinal: Double?
    /// Sideways acceleration in g (+ = toward the left), from GPS speed × yaw rate.
    public let lateral: Double
    /// Vertical acceleration in g (+ = up). Bumps show up here.
    public let vertical: Double
    /// The car's turn rate in rad/s (+ = turning left), measured around gravity.
    public let yawRate: Double
    /// Latest GPS speed in m/s, if recent and valid.
    public let speed: Double?
    /// Confidence in the learned forward axis, from 0 to 1.
    public let frameConfidence: Double
    /// `false` while the phone is being handled, dropped, or was just moved.
    public let isPhoneSettled: Bool

    public init(
        timestamp: Date,
        longitudinal: Double?,
        lateral: Double,
        vertical: Double,
        yawRate: Double,
        speed: Double?,
        frameConfidence: Double,
        isPhoneSettled: Bool,
    ) {
        self.timestamp = timestamp
        self.longitudinal = longitudinal
        self.lateral = lateral
        self.vertical = vertical
        self.yawRate = yawRate
        self.speed = speed
        self.frameConfidence = frameConfidence
        self.isPhoneSettled = isPhoneSettled
    }
}
