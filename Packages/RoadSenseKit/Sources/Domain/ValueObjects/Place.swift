import Foundation
import SensorCore

/// A destination the driver can pick from a place search.
public struct Place: Hashable, Sendable, Codable {
    public let name: String
    /// A short address line to tell similar results apart, if the map service gave one.
    public let subtitle: String?
    public let coordinate: Coordinate

    public init(name: String, subtitle: String? = nil, coordinate: Coordinate) {
        self.name = name
        self.subtitle = subtitle
        self.coordinate = coordinate
    }
}
