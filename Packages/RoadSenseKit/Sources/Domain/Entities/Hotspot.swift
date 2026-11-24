import Foundation
import SensorCore

/// What makes a hotspot dangerous. The backend decides this from the road shape.
public enum HotspotKind: String, Hashable, Sendable, Codable, CaseIterable {
    case sharpCurve
    case shortMerge
    case suddenStop
}

/// A spot where many different drivers have braked hard, or the city recorded many crashes, going in one direction.
public struct Hotspot: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let kind: HotspotKind
    public let coordinate: Coordinate
    /// The direction of travel the hotspot applies to. The same spot can be safe the other way.
    public let bearing: Bearing
    /// How many different drivers flagged it in the last 12 months.
    public let driverCount: Int
    /// Crashes the city recorded here, when the hotspot comes from its collision records instead of drivers.
    public let reportedCrashes: Int?

    public init(
        id: UUID,
        kind: HotspotKind,
        coordinate: Coordinate,
        bearing: Bearing,
        driverCount: Int,
        reportedCrashes: Int? = nil,
    ) {
        self.id = id
        self.kind = kind
        self.coordinate = coordinate
        self.bearing = bearing
        self.driverCount = driverCount
        self.reportedCrashes = reportedCrashes
    }
}
