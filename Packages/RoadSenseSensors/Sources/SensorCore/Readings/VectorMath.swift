import Foundation

/// Standard gravity in m/s². Core Motion reports acceleration in multiples of this.
public let standardGravity = 9.80665

public extension SIMD3 where Scalar == Double {
    func dot(_ other: Self) -> Double {
        (self * other).sum()
    }

    func cross(_ other: Self) -> Self {
        Self(
            y * other.z - z * other.y,
            z * other.x - x * other.z,
            x * other.y - y * other.x,
        )
    }

    var length: Double {
        dot(self).squareRoot()
    }

    /// A unit vector in the same direction, or `self` if the length is zero.
    var normalized: Self {
        let length = length
        return length > 0 ? self / length : self
    }

    /// The angle to `other`, in radians (0...π).
    func angle(to other: Self) -> Double {
        // Clamp before acos: rounding can nudge the dot product just past ±1.
        acos(Swift.min(1, Swift.max(-1, normalized.dot(other.normalized))))
    }
}

/// The signed difference `to - from` between two compass courses, in degrees (-180...180).
public func courseDifference(from: Double, to: Double) -> Double {
    // Wrap into -180...180 so 350° → 10° is a 20° turn, not 340°.
    var difference = (to - from).truncatingRemainder(dividingBy: 360)
    if difference > 180 {
        difference -= 360
    }
    if difference <= -180 {
        difference += 360
    }
    return difference
}
