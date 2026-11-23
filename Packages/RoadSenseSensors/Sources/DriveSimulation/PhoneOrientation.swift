import Foundation
import SensorCore

/// How the phone sits in the car (car axes: x forward, y left, z up).
public struct PhoneOrientation: Sendable, CustomStringConvertible {
    public let name: String
    /// Columns are the phone's x, y, z axes expressed in car coordinates.
    private let columns: (SIMD3<Double>, SIMD3<Double>)
    private let thirdColumn: SIMD3<Double>

    public init(name: String, rollDegrees: Double, pitchDegrees: Double, yawDegrees: Double) {
        self.name = name
        let roll = rollDegrees * .pi / 180
        let pitch = pitchDegrees * .pi / 180
        let yaw = yawDegrees * .pi / 180
        // R = Rz(yaw) · Ry(pitch) · Rx(roll)
        let (cosRoll, sinRoll) = (cos(roll), sin(roll))
        let (cosPitch, sinPitch) = (cos(pitch), sin(pitch))
        let (cosYaw, sinYaw) = (cos(yaw), sin(yaw))
        let xAxis = SIMD3(cosYaw * cosPitch, sinYaw * cosPitch, -sinPitch)
        let yAxis = SIMD3(
            cosYaw * sinPitch * sinRoll - sinYaw * cosRoll,
            sinYaw * sinPitch * sinRoll + cosYaw * cosRoll,
            cosPitch * sinRoll,
        )
        let zAxis = SIMD3(
            cosYaw * sinPitch * cosRoll + sinYaw * sinRoll,
            sinYaw * sinPitch * cosRoll - cosYaw * sinRoll,
            cosPitch * cosRoll,
        )
        columns = (xAxis, yAxis)
        thirdColumn = zAxis
    }

    public var description: String {
        name
    }

    /// Converts a vector from car coordinates to the phone's coordinates (Rᵀ · v).
    public func toPhone(_ vector: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(columns.0.dot(vector), columns.1.dot(vector), thirdColumn.dot(vector))
    }

    /// The car's forward axis in the phone's coordinates.
    public var forwardInPhoneFrame: SIMD3<Double> {
        toPhone(SIMD3(1, 0, 0))
    }

    public static let flat = PhoneOrientation(name: "flat", rollDegrees: 0, pitchDegrees: 0, yawDegrees: 0)
    public static let mount = PhoneOrientation(name: "mount", rollDegrees: 0, pitchDegrees: -80, yawDegrees: 180)
    public static let cupholder = PhoneOrientation(name: "cupholder", rollDegrees: 10, pitchDegrees: 70, yawDegrees: 30)
    public static let pocket = PhoneOrientation(name: "pocket", rollDegrees: 95, pitchDegrees: 20, yawDegrees: -60)

    /// A spread of realistic placements for tests.
    public static let testPlacements: [PhoneOrientation] = [.flat, .mount, .cupholder, .pocket]
}
