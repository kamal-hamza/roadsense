import Foundation
import SensorCore

/// One line of a trip log: an event, when it happened, and where the driver was.
public struct TripLogEntry: Hashable, Sendable, Codable {
    public let timestamp: Date
    /// The driver's position, or `nil` for events with no place (mute, feedback).
    public let coordinate: Coordinate?
    public let event: TripLogEvent

    public init(timestamp: Date, coordinate: Coordinate?, event: TripLogEvent) {
        self.timestamp = timestamp
        self.coordinate = coordinate
        self.event = event
    }
}
