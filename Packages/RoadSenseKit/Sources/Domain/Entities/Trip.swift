import Foundation
import SensorCore

/// A single recorded drive.
public struct Trip: Identifiable, Hashable, Sendable {
    public let id: UUID
    public private(set) var name: String
    public let startedAt: Date
    public private(set) var endedAt: Date?
    public private(set) var distance: Measurement<UnitLength>
    public private(set) var events: [DrivingEvent]

    /// Creates a trip, enforcing domain invariants.
    /// - Throws: `TripError` if the name is blank, the distance is negative, or it ends before it starts.
    public init(
        id: UUID = UUID(),
        name: String,
        startedAt: Date,
        endedAt: Date? = nil,
        distance: Measurement<UnitLength>,
        events: [DrivingEvent] = [],
    ) throws(TripError) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw .emptyName }
        guard distance.value >= 0 else { throw .negativeDistance }
        // Trips still in progress have no end time yet, so only check when there is one.
        if let endedAt, endedAt < startedAt {
            throw .endsBeforeStart
        }

        self.id = id
        self.name = trimmedName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distance = distance
        self.events = events
    }
}

/// Decoding goes through the validating initializer, so stored data can't break invariants.
extension Trip: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, startedAt, endedAt, distanceMeters, events
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Go through the validating init so a corrupted file can't create an invalid trip.
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            name: container.decode(String.self, forKey: .name),
            startedAt: container.decode(Date.self, forKey: .startedAt),
            endedAt: container.decodeIfPresent(Date.self, forKey: .endedAt),
            distance: Measurement(value: container.decode(Double.self, forKey: .distanceMeters), unit: .meters),
            events: container.decodeIfPresent([DrivingEvent].self, forKey: .events) ?? [],
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
        try container.encode(distance.converted(to: .meters).value, forKey: .distanceMeters)
        try container.encode(events, forKey: .events)
    }
}
