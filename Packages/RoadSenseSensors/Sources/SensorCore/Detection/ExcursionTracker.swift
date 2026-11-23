import Foundation

/// A stretch of time where a signal stayed above a threshold.
struct Excursion: Hashable, Sendable {
    let start: Date
    let end: Date
    let peak: Double
    let peakTime: Date

    var duration: TimeInterval {
        end.timeIntervalSince(start)
    }
}

/// Finds stretches where a signal stays above a threshold, with hysteresis so noise doesn't split them.
struct ExcursionTracker: Sendable {
    let threshold: Double
    let releaseRatio: Double

    private var start: Date?
    private var peak = 0.0
    private var peakTime: Date?

    init(threshold: Double, releaseRatio: Double = 0.7) {
        self.threshold = threshold
        self.releaseRatio = releaseRatio
    }

    /// Feeds one value (larger = more extreme). Returns the excursion once it ends.
    mutating func update(_ value: Double, at timestamp: Date) -> Excursion? {
        guard let start else {
            if value >= threshold {
                start = timestamp
                peak = value
                peakTime = timestamp
            }
            return nil
        }
        if value > peak {
            peak = value
            peakTime = timestamp
        }
        // End only once the signal drops well below the threshold (hysteresis).
        guard value < threshold * releaseRatio else { return nil }
        let excursion = Excursion(start: start, end: timestamp, peak: peak, peakTime: peakTime ?? start)
        reset()
        return excursion
    }

    mutating func reset() {
        start = nil
        peak = 0
        peakTime = nil
    }
}
