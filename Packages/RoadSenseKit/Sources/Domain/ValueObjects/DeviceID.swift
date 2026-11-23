import Foundation

/// A random, anonymous id for this install. It's the only thing linking a driver's uploads.
public struct DeviceID: Hashable, Sendable, Codable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}
