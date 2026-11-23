import Foundation
import SensorCore

/// One GPS fix near a hard brake, without its timestamp, so the backend can snap it to a road and direction.
public struct TracePoint: Hashable, Sendable, Codable {
    public let coordinate: Coordinate
    /// Direction of travel in degrees from true north, or `nil` when invalid.
    public let course: Double?

    public init(coordinate: Coordinate, course: Double?) {
        self.coordinate = coordinate
        self.course = course
    }
}
