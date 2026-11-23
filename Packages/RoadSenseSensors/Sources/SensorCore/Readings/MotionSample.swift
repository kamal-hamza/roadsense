import Foundation

/// One device-motion reading in the phone's axes; mirrors `CMDeviceMotion` without importing it.
public struct MotionSample: Hashable, Sendable, Codable {
    public let timestamp: Date
    /// Gravity direction in g, pointing toward the ground.
    public let gravity: SIMD3<Double>
    /// Acceleration the user/vehicle imparts, in g, with gravity removed.
    public let userAcceleration: SIMD3<Double>
    /// Bias-corrected rotation rate, in rad/s.
    public let rotationRate: SIMD3<Double>

    public init(
        timestamp: Date,
        gravity: SIMD3<Double>,
        userAcceleration: SIMD3<Double>,
        rotationRate: SIMD3<Double>,
    ) {
        self.timestamp = timestamp
        self.gravity = gravity
        self.userAcceleration = userAcceleration
        self.rotationRate = rotationRate
    }
}
