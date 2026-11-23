import Foundation

/// A compass direction in degrees clockwise from true north, always in `0..<360`.
public struct Bearing: Hashable, Sendable {
    public let degrees: Double

    /// Creates a bearing, wrapping any angle into `0..<360`.
    public init(degrees: Double) {
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        // truncatingRemainder keeps the sign, so pull negatives back into range.
        let positive = wrapped < 0 ? wrapped + 360 : wrapped
        // Adding 360 to a tiny negative value can round to exactly 360.
        self.degrees = positive >= 360 ? 0 : positive
    }

    /// The smallest angle to `other`, in degrees from 0 to 180.
    public func difference(to other: Bearing) -> Double {
        let raw = abs(degrees - other.degrees)
        // 350° and 10° are 20° apart, not 340°.
        return min(raw, 360 - raw)
    }

    /// Whether `other` points the same way, within `tolerance` degrees either side.
    public func isAligned(with other: Bearing, tolerance: Double) -> Bool {
        difference(to: other) <= tolerance
    }
}

/// Encoded as a plain number; decoding wraps it into range like the initializer.
extension Bearing: Codable {
    public init(from decoder: any Decoder) throws {
        try self.init(degrees: decoder.singleValueContainer().decode(Double.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(degrees)
    }
}
