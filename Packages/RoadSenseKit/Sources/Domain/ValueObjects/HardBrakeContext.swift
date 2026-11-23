import Foundation

/// The hotspot a hard brake was linked to, and whether the driver had been warned about it.
public struct HardBrakeContext: Hashable, Sendable {
    public let hotspot: RouteHotspot
    /// When the warning was given, or `nil` if there was none (suppressed or missed).
    public let warnedAt: Date?

    public init(hotspot: RouteHotspot, warnedAt: Date?) {
        self.hotspot = hotspot
        self.warnedAt = warnedAt
    }
}
