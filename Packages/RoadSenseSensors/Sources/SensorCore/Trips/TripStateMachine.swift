import Foundation

public struct TripStateMachine: Sendable {
    public enum State: Hashable, Sendable {
        case idle
        case candidate(since: Date)
        case recording(startedAt: Date, lastMovingAt: Date)
    }

    public enum Transition: Hashable, Sendable {
        case tripStarted(at: Date)
        case tripEnded(at: Date)
    }

    public struct Configuration: Sendable {
        /// Speed (m/s) that counts as driving.
        public var drivingSpeed = 5.0
        /// How long the car must keep driving speed before a trip starts.
        public var confirmationDuration: TimeInterval = 10
        /// Without motion activity, how long driving speed must last instead.
        public var confirmationDurationWithoutActivity: TimeInterval = 60
        public var candidateTimeout: TimeInterval = 120
        /// Speed (m/s) above which the car counts as moving during a trip.
        public var movingSpeed = 1.0
        public var parkedDuration: TimeInterval = 180
        public var parkedDurationAfterWalking: TimeInterval = 60

        public init() {}
    }

    public let configuration: Configuration
    public private(set) var state: State = .idle
    private var drivingSpeedSince: Date?
    private var sawAutomotive = false
    private var lastWalkingAt: Date?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Feeds one reading. Returns a transition when a trip starts or ends.
    public mutating func process(_ reading: SensorReading) -> Transition? {
        switch reading {
        case let .activity(activity):
            observe(activity)
        case let .location(location):
            observe(location)
        case .motion, .locationStatus:
            break
        }
        return evaluate(at: reading.timestamp)
    }

    private mutating func observe(_ activity: ActivitySample) {
        // The motion chip thinks we're in a car: start watching for a real trip.
        if activity.kinds.contains(.automotive), activity.confidence >= .medium {
            sawAutomotive = true
            if state == .idle {
                state = .candidate(since: activity.timestamp)
            }
        }
        if activity.isClearlyNotDriving {
            lastWalkingAt = activity.timestamp
        }
    }

    private mutating func observe(_ location: LocationSample) {
        guard let speed = location.speed else { return }
        if speed >= configuration.drivingSpeed {
            // Remember when driving speed began; any slow fix resets the clock below.
            drivingSpeedSince = drivingSpeedSince ?? location.timestamp
            if state == .idle {
                state = .candidate(since: location.timestamp)
            }
        } else {
            drivingSpeedSince = nil
        }
        // While recording, any movement pushes back the 'parked' timer.
        if case let .recording(startedAt, _) = state, speed >= configuration.movingSpeed {
            state = .recording(startedAt: startedAt, lastMovingAt: location.timestamp)
        }
    }

    private mutating func evaluate(at now: Date) -> Transition? {
        switch state {
        case .idle:
            nil
        case let .candidate(since):
            evaluateCandidate(since: since, now: now)
        case let .recording(_, lastMovingAt):
            evaluateRecording(lastMovingAt: lastMovingAt, now: now)
        }
    }

    private mutating func evaluateCandidate(since: Date, now: Date) -> Transition? {
        if let drivingSpeedSince {
            let drivingFor = now.timeIntervalSince(drivingSpeedSince)
            // Without the motion chip agreeing, demand much longer at speed (could be a bike or train).
            let required = sawAutomotive
                ? configuration.confirmationDuration
                : configuration.confirmationDurationWithoutActivity
            if drivingFor >= required {
                state = .recording(startedAt: since, lastMovingAt: now)
                // Backdate to when the candidate began; wake-ups arrive after the car is moving.
                return .tripStarted(at: since)
            }
        } else if now.timeIntervalSince(since) >= configuration.candidateTimeout {
            resetToIdle()
        }
        return nil
    }

    private mutating func evaluateRecording(lastMovingAt: Date, now: Date) -> Transition? {
        let stoppedFor = now.timeIntervalSince(lastMovingAt)
        // Walking after the last movement means the driver parked and left, so end sooner.
        let walkedAway = lastWalkingAt.map { $0 > lastMovingAt } ?? false
        let limit = walkedAway ? configuration.parkedDurationAfterWalking : configuration.parkedDuration
        guard stoppedFor >= limit else { return nil }
        resetToIdle()
        // The trip ends when the car stopped, not when we noticed.
        return .tripEnded(at: lastMovingAt)
    }

    private mutating func resetToIdle() {
        state = .idle
        drivingSpeedSince = nil
        sawAutomotive = false
        lastWalkingAt = nil
    }
}
