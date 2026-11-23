import Foundation

/// A signal pattern that looks like an event and still needs GPS confirmation.
struct DetectionCandidate: Hashable, Sendable {
    let kind: DrivingEventKind
    let excursion: Excursion
}

/// Hard braking or hard acceleration: sustained forward/backward acceleration.
struct LongitudinalEventDetector: Sendable {
    let kind: DrivingEventKind
    let minimumDuration: TimeInterval
    private var filter = LowPassFilter(cutoffHz: 2)
    private var tracker: ExcursionTracker

    init(kind: DrivingEventKind, threshold: Double, minimumDuration: TimeInterval) {
        self.kind = kind
        self.minimumDuration = minimumDuration
        tracker = ExcursionTracker(threshold: threshold)
    }

    mutating func process(_ motion: VehicleMotion) -> DetectionCandidate? {
        guard let longitudinal = motion.longitudinal else {
            reset()
            return nil
        }
        let smoothed = filter.update(longitudinal, at: motion.timestamp)
        // Flip braking so both detectors look for a positive spike.
        let signal = kind == .hardBrake ? -smoothed : smoothed
        guard let excursion = tracker.update(signal, at: motion.timestamp),
              excursion.duration >= minimumDuration
        else { return nil }
        return DetectionCandidate(kind: kind, excursion: excursion)
    }

    mutating func reset() {
        filter.reset()
        tracker.reset()
    }
}

/// Sharp turns: sustained sideways acceleration in either direction.
struct TurnDetector: Sendable {
    let minimumDuration: TimeInterval
    private var filter = LowPassFilter(cutoffHz: 1)
    private var tracker: ExcursionTracker

    init(threshold: Double, minimumDuration: TimeInterval) {
        self.minimumDuration = minimumDuration
        tracker = ExcursionTracker(threshold: threshold)
    }

    mutating func process(_ motion: VehicleMotion) -> DetectionCandidate? {
        let smoothed = filter.update(motion.lateral, at: motion.timestamp)
        // abs() so left and right turns are caught the same way.
        guard let excursion = tracker.update(abs(smoothed), at: motion.timestamp),
              excursion.duration >= minimumDuration
        else { return nil }
        return DetectionCandidate(kind: .sharpTurn, excursion: excursion)
    }

    mutating func reset() {
        filter.reset()
        tracker.reset()
    }
}

/// Swerves: a sideways push one way, then quickly the other way.
struct SwerveDetector: Sendable {
    let minimumLobeDuration: TimeInterval
    let maximumGap: TimeInterval
    private var filter = LowPassFilter(cutoffHz: 1)
    private var leftTracker: ExcursionTracker
    private var rightTracker: ExcursionTracker
    private var previousLobe: Excursion?
    private var previousLobeWasLeft = false

    init(threshold: Double, minimumLobeDuration: TimeInterval, maximumGap: TimeInterval) {
        self.minimumLobeDuration = minimumLobeDuration
        self.maximumGap = maximumGap
        leftTracker = ExcursionTracker(threshold: threshold)
        rightTracker = ExcursionTracker(threshold: threshold)
    }

    mutating func process(_ motion: VehicleMotion) -> DetectionCandidate? {
        let smoothed = filter.update(motion.lateral, at: motion.timestamp)
        // Track pushes to each side separately, then pair opposite pushes into a swerve.
        if let lobe = leftTracker.update(smoothed, at: motion.timestamp), lobe.duration >= minimumLobeDuration {
            return completeLobe(lobe, isLeft: true)
        }
        if let lobe = rightTracker.update(-smoothed, at: motion.timestamp), lobe.duration >= minimumLobeDuration {
            return completeLobe(lobe, isLeft: false)
        }
        return nil
    }

    private mutating func completeLobe(_ lobe: Excursion, isLeft: Bool) -> DetectionCandidate? {
        guard let previous = previousLobe, previousLobeWasLeft != isLeft,
              // Opposite push soon after the last one = swerve; otherwise remember this one.
              lobe.start.timeIntervalSince(previous.end) <= maximumGap
        else {
            previousLobe = lobe
            previousLobeWasLeft = isLeft
            return nil
        }
        previousLobe = nil
        let strongest = previous.peak >= lobe.peak ? previous : lobe
        let combined = Excursion(
            start: previous.start,
            end: lobe.end,
            peak: strongest.peak,
            peakTime: strongest.peakTime,
        )
        return DetectionCandidate(kind: .swerve, excursion: combined)
    }

    mutating func reset() {
        filter.reset()
        leftTracker.reset()
        rightTracker.reset()
        previousLobe = nil
    }
}

/// Bumps and potholes: short, sharp vertical spikes above the road's normal vibration.
struct BumpDetector: Sendable {
    let minimumThreshold: Double
    let vibrationMultiplier: Double
    let maximumDuration: TimeInterval
    let refractoryPeriod: TimeInterval

    private var trend = LowPassFilter(cutoffHz: 0.5)
    private var vibrationEnergy: Double?
    private var lastTimestamp: Date?
    private var spikeStart: Date?
    private var spikePeak = 0.0
    private var spikePeakTime: Date?
    private var lastBumpEnd: Date?

    init(
        minimumThreshold: Double,
        vibrationMultiplier: Double,
        maximumDuration: TimeInterval,
        refractoryPeriod: TimeInterval,
    ) {
        self.minimumThreshold = minimumThreshold
        self.vibrationMultiplier = vibrationMultiplier
        self.maximumDuration = maximumDuration
        self.refractoryPeriod = refractoryPeriod
    }

    mutating func process(_ motion: VehicleMotion) -> DetectionCandidate? {
        // Subtract the slow trend (hills, pitch under braking) to leave only jolts.
        let highPassed = motion.vertical - trend.update(motion.vertical, at: motion.timestamp)
        let magnitude = abs(highPassed)
        // Rough roads raise the bar, so normal vibration there isn't a stream of bumps.
        let threshold = max(minimumThreshold, vibrationMultiplier * (vibrationEnergy ?? 0).squareRoot())
        updateVibration(highPassed * highPassed, at: motion.timestamp)

        guard let start = spikeStart else {
            if magnitude >= threshold {
                spikeStart = motion.timestamp
                spikePeak = magnitude
                spikePeakTime = motion.timestamp
            }
            return nil
        }
        if magnitude > spikePeak {
            spikePeak = magnitude
            spikePeakTime = motion.timestamp
        }
        guard magnitude < threshold * 0.7 else { return nil }

        let excursion = Excursion(
            start: start,
            end: motion.timestamp,
            peak: spikePeak,
            peakTime: spikePeakTime ?? start,
        )
        spikeStart = nil
        // Bumps are short; long vertical motion is a dip or ramp. Ignore echoes right after a bump.
        let isSpike = excursion.duration <= maximumDuration
        let isOutsideRefractory = lastBumpEnd.map { start.timeIntervalSince($0) >= refractoryPeriod } ?? true
        guard isSpike, isOutsideRefractory else { return nil }
        lastBumpEnd = motion.timestamp
        return DetectionCandidate(kind: .bump, excursion: excursion)
    }

    /// Tracks the road's typical vibration (≈10 s memory) so rough roads need bigger spikes.
    private mutating func updateVibration(_ energy: Double, at timestamp: Date) {
        defer { lastTimestamp = timestamp }
        guard let current = vibrationEnergy, let lastTimestamp else {
            vibrationEnergy = energy
            return
        }
        let elapsed = max(0, timestamp.timeIntervalSince(lastTimestamp))
        let smoothing = elapsed / (10 + elapsed)
        vibrationEnergy = current + smoothing * (energy - current)
    }

    mutating func reset() {
        spikeStart = nil
        spikePeak = 0
        spikePeakTime = nil
    }
}
