import Foundation

/// What gets logged about a hard brake (activity diagram 5).
public struct HardBrakeRecord: Hashable, Sendable, Codable {
    /// Direction of travel before braking, in degrees from true north.
    public let course: Double?
    /// Speeds in m/s just before and after the brake.
    public let speedBefore: Double?
    public let speedAfter: Double?
    /// Peak deceleration, in g.
    public let peakDeceleration: Double
    public let nearestHotspotID: UUID?
    public let wasWarned: Bool
    public let secondsSinceWarning: Double?
    /// A few GPS fixes around the brake.
    public let trace: [TracePoint]

    public init(
        course: Double?,
        speedBefore: Double?,
        speedAfter: Double?,
        peakDeceleration: Double,
        nearestHotspotID: UUID?,
        wasWarned: Bool,
        secondsSinceWarning: Double?,
        trace: [TracePoint],
    ) {
        self.course = course
        self.speedBefore = speedBefore
        self.speedAfter = speedAfter
        self.peakDeceleration = peakDeceleration
        self.nearestHotspotID = nearestHotspotID
        self.wasWarned = wasWarned
        self.secondsSinceWarning = secondsSinceWarning
        self.trace = trace
    }

    /// The same record with a different trace (used when trimming fixes near home or work).
    public func withTrace(_ newTrace: [TracePoint]) -> HardBrakeRecord {
        HardBrakeRecord(
            course: course,
            speedBefore: speedBefore,
            speedAfter: speedAfter,
            peakDeceleration: peakDeceleration,
            nearestHotspotID: nearestHotspotID,
            wasWarned: wasWarned,
            secondsSinceWarning: secondsSinceWarning,
            trace: newTrace,
        )
    }
}
