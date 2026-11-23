import Foundation

/// Learns the car's up, forward, and yaw axes from phone sensors, wherever the phone sits. See docs/SENSORS.md §4.
public struct VehicleFrameEstimator: Sendable {
    public struct Configuration: Sendable {
        /// Minimum |Δspeed/Δt| (in g) for a GPS interval to teach the forward axis.
        public var minimumTrainingAcceleration = 0.08
        /// Maximum average |yaw rate| (rad/s) for a GPS interval to count as straight.
        public var maximumTrainingYawRate = 0.05
        public var minimumTrainingSpeed = 3.0
        public var minimumTrainingPairs = 5
        public var maximumTrainingPairs = 120
        /// Minimum correlation between phone and GPS acceleration before the frame is trusted.
        public var minimumCorrelation = 0.6
        /// Gravity direction change (radians) that means the phone was moved.
        public var phoneMovedAngle = 15.0 * .pi / 180
        /// Disagreement (radians) between phone yaw and GPS course change that means the phone was rotated.
        public var phoneRotatedAngle = 20.0 * .pi / 180
        /// Rotation (rad/s) around non-vertical axes that means someone is handling the phone.
        public var handlingRotationRate = 1.0
        /// Total acceleration (g) below which the phone is in free fall.
        public var freeFallAcceleration = 0.3
        public var freeFallDuration: TimeInterval = 0.08
        /// How long events are suppressed after the phone is moved, handled, or dropped.
        public var settleDuration: TimeInterval = 2
        /// GPS fixes older than this aren't used for speed.
        public var maximumLocationAge: TimeInterval = 3

        public init() {}
    }

    private struct TrainingPair: Sendable {
        let horizontalAcceleration: SIMD3<Double>
        let speedChange: Double
    }

    /// Sensor data gathered between two GPS fixes.
    private struct Interval: Sendable {
        var accelerationSum = SIMD3<Double>.zero
        var absoluteYawSum = 0.0
        var integratedYaw = 0.0
        var sampleCount = 0
    }

    public let configuration: Configuration

    /// The car's forward axis in the phone's frame, once learned.
    public private(set) var forward: SIMD3<Double>?
    public private(set) var confidence = 0.0

    private var smoothedUp: SIMD3<Double>?
    private var referenceUp: SIMD3<Double>?
    private var pairs: [TrainingPair] = []
    private var interval = Interval()
    private var lastLocation: LocationSample?
    private var lastMotionTimestamp: Date?
    private var freeFallStart: Date?
    private var unsettledUntil: Date?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// `true` once braking/acceleration can be measured reliably.
    public var isFrameReady: Bool {
        forward != nil && pairs.count >= configuration.minimumTrainingPairs
            && confidence >= configuration.minimumCorrelation
    }

    /// Converts one phone-frame sample into the car's frame.
    public mutating func process(_ sample: MotionSample) -> VehicleMotion {
        let up = updateUp(with: sample)
        // Rotation around gravity is the car turning, whatever angle the phone sits at.
        let yawRate = sample.rotationRate.dot(up)
        detectHandling(sample, up: up, yawRate: yawRate)

        // Split acceleration into vertical (bumps) and horizontal (braking, cornering).
        let vertical = sample.userAcceleration.dot(up)
        let horizontal = sample.userAcceleration - vertical * up
        accumulate(horizontal: horizontal, yawRate: yawRate, at: sample.timestamp)

        let speed = recentSpeed(at: sample.timestamp)
        return VehicleMotion(
            timestamp: sample.timestamp,
            longitudinal: isFrameReady ? forward.map { horizontal.dot($0) } : nil,
            // Centripetal acceleration = speed × turn rate, so cornering needs no forward axis.
            lateral: (speed ?? 0) * yawRate / standardGravity,
            vertical: vertical,
            yawRate: yawRate,
            speed: speed,
            frameConfidence: confidence,
            isPhoneSettled: unsettledUntil.map { sample.timestamp >= $0 } ?? true,
        )
    }

    /// Uses a GPS fix to learn the forward axis and check that the phone hasn't rotated.
    public mutating func process(_ location: LocationSample) {
        // Always start a fresh interval, even when this fix can't be used for training.
        defer {
            interval = Interval()
            lastLocation = location.speed == nil ? nil : location
        }
        guard let previous = lastLocation, let speed = location.speed, let previousSpeed = previous.speed,
              interval.sampleCount > 0
        else { return }
        let elapsed = location.timestamp.timeIntervalSince(previous.timestamp)
        // Skip fixes that are too close together (noisy) or too far apart (stale).
        guard elapsed >= 0.5, elapsed <= 3 else { return }

        if phoneRotatedRelativeToCar(from: previous, to: location) {
            resetFrame(at: location.timestamp)
            return
        }

        // Only learn from straight-line speed changes; turns would smear the forward axis.
        let speedChange = (speed - previousSpeed) / elapsed / standardGravity
        let averageYawRate = interval.absoluteYawSum / Double(interval.sampleCount)
        guard abs(speedChange) >= configuration.minimumTrainingAcceleration,
              averageYawRate <= configuration.maximumTrainingYawRate,
              max(speed, previousSpeed) >= configuration.minimumTrainingSpeed
        else { return }

        let averageAcceleration = interval.accelerationSum / Double(interval.sampleCount)
        pairs.append(TrainingPair(horizontalAcceleration: averageAcceleration, speedChange: speedChange))
        // Keep a rolling window so old pairs don't outweigh the current placement.
        if pairs.count > configuration.maximumTrainingPairs {
            pairs.removeFirst(pairs.count - configuration.maximumTrainingPairs)
        }
        relearnForward()
    }

    // MARK: - Steps

    private mutating func updateUp(with sample: MotionSample) -> SIMD3<Double> {
        let up = -sample.gravity.normalized
        // Smooth out road vibration so only a real re-seat of the phone moves this.
        let smoothed = smoothedUp.map { ($0 * 0.9 + up * 0.1).normalized } ?? up
        smoothedUp = smoothed
        if let referenceUp {
            // Gravity swung too far: the phone was moved, so the learned axis is wrong now.
            if smoothed.angle(to: referenceUp) > configuration.phoneMovedAngle {
                resetFrame(at: sample.timestamp)
                self.referenceUp = smoothed
            }
        } else {
            referenceUp = smoothed
        }
        return up
    }

    private mutating func detectHandling(_ sample: MotionSample, up: SIMD3<Double>, yawRate: Double) {
        // Cars only rotate around vertical; tilting or flipping means a hand is on the phone.
        let offAxisRotation = (sample.rotationRate - yawRate * up).length
        if offAxisRotation > configuration.handlingRotationRate {
            unsettle(at: sample.timestamp)
        }

        // Near-zero total acceleration for a moment means the phone is falling.
        let totalAcceleration = (sample.gravity + sample.userAcceleration).length
        if totalAcceleration < configuration.freeFallAcceleration {
            let start = freeFallStart ?? sample.timestamp
            freeFallStart = start
            if sample.timestamp.timeIntervalSince(start) >= configuration.freeFallDuration {
                unsettle(at: sample.timestamp)
            }
        } else {
            freeFallStart = nil
        }
    }

    private mutating func accumulate(horizontal: SIMD3<Double>, yawRate: Double, at timestamp: Date) {
        let elapsed = lastMotionTimestamp.map { max(0, timestamp.timeIntervalSince($0)) } ?? 0
        lastMotionTimestamp = timestamp
        interval.accelerationSum += horizontal
        interval.absoluteYawSum += abs(yawRate)
        // Cap the step so a sensor gap can't fake a big rotation.
        interval.integratedYaw += yawRate * min(elapsed, 0.1)
        interval.sampleCount += 1
    }

    private func recentSpeed(at timestamp: Date) -> Double? {
        guard let lastLocation, timestamp.timeIntervalSince(lastLocation.timestamp) <= configuration.maximumLocationAge
        else { return nil }
        return lastLocation.speed
    }

    /// Compares the phone's own rotation with the GPS course change over one interval.
    private func phoneRotatedRelativeToCar(from previous: LocationSample, to location: LocationSample) -> Bool {
        guard let previousCourse = previous.course, let course = location.course,
              (previous.speed ?? 0) >= configuration.minimumTrainingSpeed,
              (location.speed ?? 0) >= configuration.minimumTrainingSpeed
        else { return false }
        // Course is clockwise; yaw is counterclockwise.
        let expectedYaw = -courseDifference(from: previousCourse, to: course) * .pi / 180
        return abs(interval.integratedYaw - expectedYaw) > configuration.phoneRotatedAngle
    }

    private mutating func relearnForward() {
        guard let up = smoothedUp else { return }
        // Least squares: Σ(accel × Δspeed) points forward (braking pairs flip sign and still agree).
        let weighted = pairs.reduce(SIMD3<Double>.zero) { $0 + $1.horizontalAcceleration * $1.speedChange }
        // Drop any vertical part so forward lies flat in the road plane.
        let horizontal = weighted - weighted.dot(up) * up
        guard horizontal.length > 1e-6 else { return }
        let candidate = horizontal.normalized
        forward = candidate

        // Confidence = how well phone acceleration along that axis tracks GPS speed changes.
        let correlation = Self.correlation(
            pairs.map { $0.horizontalAcceleration.dot(candidate) },
            pairs.map(\.speedChange),
        )
        let coverage = min(1, Double(pairs.count) / Double(configuration.minimumTrainingPairs))
        confidence = max(0, correlation) * coverage
    }

    private mutating func resetFrame(at timestamp: Date) {
        forward = nil
        confidence = 0
        pairs.removeAll()
        interval = Interval()
        unsettle(at: timestamp)
    }

    private mutating func unsettle(at timestamp: Date) {
        unsettledUntil = timestamp.addingTimeInterval(configuration.settleDuration)
    }

    /// Pearson correlation coefficient, or 0 when undefined.
    static func correlation(_ xs: [Double], _ ys: [Double]) -> Double {
        let count = Double(xs.count)
        guard xs.count == ys.count, xs.count >= 2 else { return 0 }
        let meanX = xs.reduce(0, +) / count
        let meanY = ys.reduce(0, +) / count
        var covariance = 0.0, varianceX = 0.0, varianceY = 0.0
        for (x, y) in zip(xs, ys) {
            covariance += (x - meanX) * (y - meanY)
            varianceX += (x - meanX) * (x - meanX)
            varianceY += (y - meanY) * (y - meanY)
        }
        let denominator = (varianceX * varianceY).squareRoot()
        return denominator > 0 ? covariance / denominator : 0
    }
}
