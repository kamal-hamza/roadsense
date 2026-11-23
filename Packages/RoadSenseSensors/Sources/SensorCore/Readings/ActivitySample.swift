import Foundation

/// The system's guess at how the device is moving. Kinds can overlap (automotive + stationary).
public struct ActivitySample: Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable, CaseIterable {
        case stationary, walking, running, cycling, automotive, unknown
    }

    public enum Confidence: Int, Hashable, Sendable, Codable, Comparable {
        case low, medium, high

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let timestamp: Date
    public let kinds: Set<Kind>
    public let confidence: Confidence

    public init(timestamp: Date, kinds: Set<Kind>, confidence: Confidence) {
        self.timestamp = timestamp
        self.kinds = kinds
        self.confidence = confidence
    }

    /// `true` if the device is confidently on a person moving under their own power.
    public var isClearlyNotDriving: Bool {
        confidence >= .medium
            && !kinds.contains(.automotive)
            && !kinds.isDisjoint(with: [.walking, .running, .cycling])
    }
}
