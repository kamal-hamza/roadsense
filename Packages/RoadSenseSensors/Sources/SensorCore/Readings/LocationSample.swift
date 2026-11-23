import Foundation

/// One GPS fix. Invalid speed or course values are represented as `nil`.
public struct LocationSample: Hashable, Sendable, Codable {
    public let timestamp: Date
    public let coordinate: Coordinate
    /// Radius of uncertainty, in meters.
    public let horizontalAccuracy: Double
    /// Speed in m/s, or `nil` when the GPS reports it as invalid.
    public let speed: Double?
    public let speedAccuracy: Double?
    /// Direction of travel in degrees clockwise from true north, or `nil` when invalid.
    public let course: Double?
    public let courseAccuracy: Double?

    public init(
        timestamp: Date,
        coordinate: Coordinate,
        horizontalAccuracy: Double,
        speed: Double?,
        speedAccuracy: Double?,
        course: Double?,
        courseAccuracy: Double?,
    ) {
        self.timestamp = timestamp
        self.coordinate = coordinate
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed
        self.speedAccuracy = speedAccuracy
        self.course = course
        self.courseAccuracy = courseAccuracy
    }
}
