import Foundation

/// Turns sensor readings into driving events, confirming each candidate against GPS.
public struct DetectionPipeline: Sendable {
    public struct Configuration: Sendable {
        public var hardBrakeThreshold = 0.30
        public var hardBrakeMinimumDuration: TimeInterval = 0.4
        public var hardAccelerationThreshold = 0.25
        public var hardAccelerationMinimumDuration: TimeInterval = 0.5
        public var sharpTurnThreshold = 0.35
        public var sharpTurnMinimumDuration: TimeInterval = 0.5
        public var sharpTurnMinimumCourseChange = 30.0
        public var swerveThreshold = 0.25
        public var swerveMaximumCourseChange = 15.0
        public var bumpThreshold = 0.5
        /// Minimum speed (m/s) for any event to count.
        public var minimumEventSpeed = 5.0
        public var minimumSwerveSpeed = 10.0
        /// A brake/acceleration must change GPS speed by at least this much (m/s)...
        public var minimumSpeedChange = 1.0
        /// ...and by at least this fraction of what the accelerometer implies.
        public var speedChangeFraction = 0.4
        /// How long after a candidate ends to wait for the confirming GPS fix.
        public var confirmationDelay: TimeInterval = 0.5
        /// Candidates without a confirming GPS fix by then are dropped.
        public var confirmationTimeout: TimeInterval = 4
        public var activityMaximumAge: TimeInterval = 120
        public var frame = VehicleFrameEstimator.Configuration()

        public init() {}
    }

    public let configuration: Configuration
    private var estimator: VehicleFrameEstimator
    private var hardBrake: LongitudinalEventDetector
    private var hardAcceleration: LongitudinalEventDetector
    private var sharpTurn: TurnDetector
    private var swerve: SwerveDetector
    private var bump: BumpDetector
    private var pending: [DetectionCandidate] = []
    private var recentLocations: [LocationSample] = []
    private var latestActivity: ActivitySample?

    /// The most recent motion sample in the car's frame (for live display).
    public private(set) var latestMotion: VehicleMotion?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        estimator = VehicleFrameEstimator(configuration: configuration.frame)
        hardBrake = LongitudinalEventDetector(
            kind: .hardBrake,
            threshold: configuration.hardBrakeThreshold,
            minimumDuration: configuration.hardBrakeMinimumDuration,
        )
        hardAcceleration = LongitudinalEventDetector(
            kind: .hardAcceleration,
            threshold: configuration.hardAccelerationThreshold,
            minimumDuration: configuration.hardAccelerationMinimumDuration,
        )
        sharpTurn = TurnDetector(
            threshold: configuration.sharpTurnThreshold,
            minimumDuration: configuration.sharpTurnMinimumDuration,
        )
        swerve = SwerveDetector(threshold: configuration.swerveThreshold, minimumLobeDuration: 0.2, maximumGap: 2.5)
        bump = BumpDetector(
            minimumThreshold: configuration.bumpThreshold,
            vibrationMultiplier: 5,
            maximumDuration: 0.3,
            refractoryPeriod: 1,
        )
    }

    public var isFrameReady: Bool {
        estimator.isFrameReady
    }

    public var frameConfidence: Double {
        estimator.confidence
    }

    /// Processes one reading and returns any events it confirmed.
    public mutating func process(_ reading: SensorReading) -> [DrivingEvent] {
        switch reading {
        case let .motion(sample):
            return process(motion: sample)
        case let .location(sample):
            return process(location: sample)
        case let .activity(sample):
            latestActivity = sample
            return []
        case .locationStatus:
            return []
        }
    }

    // MARK: - Motion

    private mutating func process(motion sample: MotionSample) -> [DrivingEvent] {
        let motion = estimator.process(sample)
        latestMotion = motion
        let timeout = configuration.confirmationTimeout
        // Drop candidates whose confirming GPS fix never arrived.
        pending.removeAll { sample.timestamp.timeIntervalSince($0.excursion.end) > timeout }
        // Handling the phone or walking around would look like events, so pause detection.
        guard motion.isPhoneSettled, !isClearlyNotDriving(at: sample.timestamp) else {
            resetDetectors()
            return []
        }

        // These need a GPS check later; bumps below are short enough to accept right away.
        let candidates = [
            hardBrake.process(motion),
            hardAcceleration.process(motion),
            sharpTurn.process(motion),
            swerve.process(motion),
        ].compactMap(\.self)
        pending.append(contentsOf: candidates)

        guard let bumpCandidate = bump.process(motion),
              let speed = motion.speed, speed >= configuration.minimumEventSpeed
        else { return [] }
        return [makeEvent(from: bumpCandidate, speed: speed, course: recentLocations.last?.course, confidence: 1)]
    }

    private func isClearlyNotDriving(at timestamp: Date) -> Bool {
        guard let latestActivity,
              timestamp.timeIntervalSince(latestActivity.timestamp) <= configuration.activityMaximumAge
        else { return false }
        return latestActivity.isClearlyNotDriving
    }

    private mutating func resetDetectors() {
        hardBrake.reset()
        hardAcceleration.reset()
        sharpTurn.reset()
        swerve.reset()
        bump.reset()
    }

    // MARK: - Location and confirmation

    private mutating func process(location sample: LocationSample) -> [DrivingEvent] {
        estimator.process(sample)
        recentLocations.append(sample)
        recentLocations.removeAll { sample.timestamp.timeIntervalSince($0.timestamp) > 30 }

        var confirmed: [DrivingEvent] = []
        var stillPending: [DetectionCandidate] = []
        // A candidate can be judged once there's a fix from after it ended.
        for candidate in pending {
            if sample.timestamp >= candidate.excursion.end.addingTimeInterval(configuration.confirmationDelay) {
                if let event = confirm(candidate) {
                    confirmed.append(event)
                }
            } else {
                stillPending.append(candidate)
            }
        }
        pending = stillPending
        return confirmed
    }

    private func confirm(_ candidate: DetectionCandidate) -> DrivingEvent? {
        let excursion = candidate.excursion
        let confirmAfter = excursion.end.addingTimeInterval(configuration.confirmationDelay)
        // GPS fixes from just before the event started and just after it ended.
        guard let before = recentLocations.last(where: { $0.timestamp <= excursion.start && $0.speed != nil }),
              let after = recentLocations.first(where: { $0.timestamp >= confirmAfter && $0.speed != nil }),
              let speedBefore = before.speed, let speedAfter = after.speed
        else { return nil }

        // Each kind must show up in GPS too: speed drop, speed gain, or course change.
        let isConfirmed = switch candidate.kind {
        case .hardBrake:
            speedBefore >= configuration.minimumEventSpeed
                && speedBefore - speedAfter >= requiredSpeedChange(for: excursion)
        case .hardAcceleration:
            speedAfter >= configuration.minimumEventSpeed
                && speedAfter - speedBefore >= requiredSpeedChange(for: excursion)
        case .sharpTurn:
            speedBefore >= configuration.minimumEventSpeed
                && courseChange(from: before, to: after)
                .map { $0 >= configuration.sharpTurnMinimumCourseChange } == true
        case .swerve:
            speedBefore >= configuration.minimumSwerveSpeed
                && courseChange(from: before, to: after).map { $0 <= configuration.swerveMaximumCourseChange } == true
        case .bump:
            true
        }
        guard isConfirmed else { return nil }

        let usesForwardAxis = candidate.kind == .hardBrake || candidate.kind == .hardAcceleration
        return makeEvent(
            from: candidate,
            speed: interpolatedSpeed(at: excursion.peakTime) ?? speedBefore,
            course: before.course,
            confidence: usesForwardAxis ? estimator.confidence : 1,
        )
    }

    private func requiredSpeedChange(for excursion: Excursion) -> Double {
        // Speed change the accelerometer implies (m/s); GPS must show a decent share of it.
        let implied = excursion.peak * standardGravity * excursion.duration
        return max(configuration.minimumSpeedChange, configuration.speedChangeFraction * implied)
    }

    private func courseChange(from before: LocationSample, to after: LocationSample) -> Double? {
        guard let start = before.course, let end = after.course else { return nil }
        return abs(courseDifference(from: start, to: end))
    }

    private func makeEvent(
        from candidate: DetectionCandidate,
        speed: Double?,
        course: Double?,
        confidence: Double,
    ) -> DrivingEvent {
        DrivingEvent(
            kind: candidate.kind,
            timestamp: candidate.excursion.peakTime,
            duration: candidate.excursion.duration,
            peakAcceleration: candidate.excursion.peak,
            speed: speed,
            course: course,
            coordinate: interpolatedCoordinate(at: candidate.excursion.peakTime),
            confidence: confidence,
        )
    }

    // MARK: - Interpolation between GPS fixes

    private func bracketingLocations(at timestamp: Date) -> (before: LocationSample, after: LocationSample?)? {
        guard let before = recentLocations.last(where: { $0.timestamp <= timestamp }) else {
            // Event happened before our first fix; the earliest fix is the best guess.
            return recentLocations.first.map { ($0, nil) }
        }
        return (before, recentLocations.first { $0.timestamp > timestamp })
    }

    private func interpolatedCoordinate(at timestamp: Date) -> Coordinate? {
        guard let bracket = bracketingLocations(at: timestamp) else { return nil }
        guard let after = bracket.after else { return bracket.before.coordinate }
        let fraction = Self.fraction(of: timestamp, between: bracket.before.timestamp, and: after.timestamp)
        return bracket.before.coordinate.interpolated(to: after.coordinate, fraction: fraction)
    }

    private func interpolatedSpeed(at timestamp: Date) -> Double? {
        guard let bracket = bracketingLocations(at: timestamp), let speedBefore = bracket.before.speed else {
            return nil
        }
        guard let after = bracket.after, let speedAfter = after.speed else { return speedBefore }
        let fraction = Self.fraction(of: timestamp, between: bracket.before.timestamp, and: after.timestamp)
        return speedBefore + (speedAfter - speedBefore) * fraction
    }

    private static func fraction(of timestamp: Date, between start: Date, and end: Date) -> Double {
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return 0 }
        return min(1, max(0, timestamp.timeIntervalSince(start) / span))
    }
}
