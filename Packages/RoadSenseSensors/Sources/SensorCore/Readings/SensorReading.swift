import Foundation

/// Location-service conditions that stop or degrade GPS readings.
public enum LocationStatus: String, Hashable, Sendable, Codable {
    case requestingAuthorization
    case denied
    case restricted
    case accuracyLimited
    case needsForeground
    case unavailable
    case stationary
}

public struct LocationStatusUpdate: Hashable, Sendable, Codable {
    public let timestamp: Date
    public let status: LocationStatus

    public init(timestamp: Date, status: LocationStatus) {
        self.timestamp = timestamp
        self.status = status
    }
}

/// Any sensor reading. Live, replayed, and simulated sources all produce this type.
public enum SensorReading: Hashable, Sendable {
    case motion(MotionSample)
    case location(LocationSample)
    case activity(ActivitySample)
    case locationStatus(LocationStatusUpdate)

    public var timestamp: Date {
        switch self {
        case let .motion(sample): sample.timestamp
        case let .location(sample): sample.timestamp
        case let .activity(sample): sample.timestamp
        case let .locationStatus(update): update.timestamp
        }
    }
}

/// Encoded as `{"type": "motion", "data": {...}}`, one reading per line in sensor logs.
extension SensorReading: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, data
    }

    private enum Kind: String, Codable {
        case motion, location, activity, locationStatus
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // // Read the "type" tag first, then decode "data" as the matching sample type.
        switch try container.decode(Kind.self, forKey: .type) {
        case .motion: self = try .motion(container.decode(MotionSample.self, forKey: .data))
        case .location: self = try .location(container.decode(LocationSample.self, forKey: .data))
        case .activity: self = try .activity(container.decode(ActivitySample.self, forKey: .data))
        case .locationStatus: self = try .locationStatus(container.decode(LocationStatusUpdate.self, forKey: .data))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .motion(sample):
            try container.encode(Kind.motion, forKey: .type)
            try container.encode(sample, forKey: .data)
        case let .location(sample):
            try container.encode(Kind.location, forKey: .type)
            try container.encode(sample, forKey: .data)
        case let .activity(sample):
            try container.encode(Kind.activity, forKey: .type)
            try container.encode(sample, forKey: .data)
        case let .locationStatus(update):
            try container.encode(Kind.locationStatus, forKey: .type)
            try container.encode(update, forKey: .data)
        }
    }
}
