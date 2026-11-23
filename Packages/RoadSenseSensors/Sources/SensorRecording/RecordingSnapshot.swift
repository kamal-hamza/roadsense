import Foundation
import SensorCore

/// The live state of a recording, published for display.
public struct RecordingSnapshot: Hashable, Sendable {
    public let recordingID: UUID
    public let startedAt: Date
    /// Sensor time of the reading that produced this snapshot; "now" for replayed and simulated drives too.
    public let timestamp: Date
    public let speed: Double?
    /// The latest GPS fix, so apps can follow the drive without a second sensor stream.
    public let location: LocationSample?
    public let distanceMeters: Double
    public let motion: VehicleMotion?
    public let isFrameReady: Bool
    public let frameConfidence: Double
    public let activity: ActivitySample?
    public let locationStatus: LocationStatus?
    public let events: [DrivingEvent]
    public let isLoggingRawSensors: Bool

    public init(
        recordingID: UUID,
        startedAt: Date,
        timestamp: Date,
        speed: Double?,
        location: LocationSample?,
        distanceMeters: Double,
        motion: VehicleMotion?,
        isFrameReady: Bool,
        frameConfidence: Double,
        activity: ActivitySample?,
        locationStatus: LocationStatus?,
        events: [DrivingEvent],
        isLoggingRawSensors: Bool,
    ) {
        self.recordingID = recordingID
        self.startedAt = startedAt
        self.timestamp = timestamp
        self.speed = speed
        self.location = location
        self.distanceMeters = distanceMeters
        self.motion = motion
        self.isFrameReady = isFrameReady
        self.frameConfidence = frameConfidence
        self.activity = activity
        self.locationStatus = locationStatus
        self.events = events
        self.isLoggingRawSensors = isLoggingRawSensors
    }
}
