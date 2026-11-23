import Foundation
import SensorCore

/// The live state of a recording, published for display.
public struct RecordingSnapshot: Hashable, Sendable {
    public let recordingID: UUID
    public let startedAt: Date
    public let speed: Double?
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
        speed: Double?,
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
        self.speed = speed
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
