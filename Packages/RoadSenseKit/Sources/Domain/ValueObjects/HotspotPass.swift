import Foundation

/// The driver went past a hotspot.
public struct HotspotPass: Hashable, Sendable {
    public let hotspot: RouteHotspot
    public let outcome: HotspotPassOutcome
    /// Whether a hard brake was linked to this hotspot on the way past.
    public let brakedHard: Bool
    /// Best estimate of when the driver reached the hotspot.
    public let timestamp: Date

    public init(hotspot: RouteHotspot, outcome: HotspotPassOutcome, brakedHard: Bool, timestamp: Date) {
        self.hotspot = hotspot
        self.outcome = outcome
        self.brakedHard = brakedHard
        self.timestamp = timestamp
    }
}
