import Foundation

/// The kinds of driving event RoadSense detects.
public enum DrivingEventKind: String, Hashable, Sendable, Codable, CaseIterable {
    case hardBrake
    case hardAcceleration
    case sharpTurn
    case swerve
    case bump
}

/// A detected moment of hard braking, cornering, swerving, or a road bump.
public struct DrivingEvent: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let kind: DrivingEventKind
    /// When the signal peaked.
    public let timestamp: Date
    public let duration: TimeInterval
    /// Peak acceleration magnitude, in g.
    public let peakAcceleration: Double
    /// Vehicle speed at the peak, in m/s.
    public let speed: Double?
    /// Direction of travel before the event, in degrees from true north.
    public let course: Double?
    public let coordinate: Coordinate?
    /// How much to trust the detection, from 0 to 1.
    public let confidence: Double

    public init(
        id: UUID = UUID(),
        kind: DrivingEventKind,
        timestamp: Date,
        duration: TimeInterval,
        peakAcceleration: Double,
        speed: Double?,
        course: Double?,
        coordinate: Coordinate?,
        confidence: Double,
    ) {
        self.id = id
        self.kind = kind
        self.timestamp = timestamp
        self.duration = duration
        self.peakAcceleration = peakAcceleration
        self.speed = speed
        self.course = course
        self.coordinate = coordinate
        self.confidence = confidence
    }
}
