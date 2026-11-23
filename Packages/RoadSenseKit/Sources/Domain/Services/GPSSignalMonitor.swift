import Foundation
import SensorCore

/// How trustworthy the GPS is right now.
public enum GPSStatus: Hashable, Sendable {
    /// Recent and accurate enough to warn from.
    case good
    /// Inaccurate or stale (tunnel, urban canyon). Warnings pause, but it's too early to tell the driver.
    case degraded
    /// No good fix for a while; show "GPS signal lost".
    case lost
}

/// Decides whether each GPS fix is good enough to warn from, and when the signal counts as lost.
public struct GPSSignalMonitor: Sendable {
    public struct Configuration: Hashable, Sendable {
        /// Worst acceptable accuracy radius, in meters.
        public var maximumAccuracy = 30.0
        /// Oldest acceptable fix, in seconds.
        public var maximumAge: TimeInterval = 3
        /// Seconds without a good fix before the signal counts as lost.
        public var lostAfter: TimeInterval = 30

        public init() {}
    }

    public let configuration: Configuration
    /// The latest fix that passed the checks; warnings fall back to it while the signal is degraded.
    public private(set) var lastGoodFix: LocationSample?
    /// When we started waiting for a first good fix.
    private var waitingSince: Date?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Checks a new fix and returns the signal status at `now`.
    public mutating func process(_ fix: LocationSample, at now: Date) -> GPSStatus {
        // Negative accuracy means Core Location considers the fix invalid.
        let isAccurate = fix.horizontalAccuracy >= 0 && fix.horizontalAccuracy <= configuration.maximumAccuracy
        let isFresh = now.timeIntervalSince(fix.timestamp) <= configuration.maximumAge
        if isAccurate, isFresh {
            lastGoodFix = fix
        } else if waitingSince == nil {
            waitingSince = now
        }
        return status(at: now)
    }

    /// The signal status at `now`, also useful when no fix has arrived for a while.
    public func status(at now: Date) -> GPSStatus {
        if let lastGoodFix, now.timeIntervalSince(lastGoodFix.timestamp) <= configuration.maximumAge {
            return .good
        }
        // Measure the outage from the last good fix, or from when we started if there never was one.
        guard let since = lastGoodFix?.timestamp ?? waitingSince else { return .degraded }
        return now.timeIntervalSince(since) >= configuration.lostAfter ? .lost : .degraded
    }
}
