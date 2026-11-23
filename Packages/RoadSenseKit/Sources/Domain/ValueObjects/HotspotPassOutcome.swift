import Foundation

/// How the driver went past a hotspot. Warned vs unwarned passes feed success metric 1.
public enum HotspotPassOutcome: Hashable, Sendable, Codable {
    /// Warned in time; `secondsOfWarning` is how long before reaching the hotspot.
    case warned(secondsOfWarning: Double)
    /// A warning was due but warnings were muted.
    case suppressed
    /// Passed without a warning (GPS gap, or heading didn't match).
    case missed
}
