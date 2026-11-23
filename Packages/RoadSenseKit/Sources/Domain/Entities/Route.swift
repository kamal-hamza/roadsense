import Foundation
import SensorCore

/// A driving route: the line on the map from the start to the destination.
public struct Route: Hashable, Sendable {
    /// What the map service calls this route (e.g. "I-5 N"), for telling alternatives apart.
    public let name: String
    public let points: [Coordinate]
    /// Expected driving time in seconds.
    public let expectedTravelTime: TimeInterval
    public let segments: [RouteSegment]

    /// Total length in meters.
    public var length: Double {
        segments.last.map { $0.distanceFromStart + $0.length } ?? 0
    }

    /// Creates a route, dropping repeated points.
    /// - Throws: `RouteError` if fewer than two distinct points remain or the travel time is negative.
    public init(name: String, points: [Coordinate], expectedTravelTime: TimeInterval) throws(RouteError) {
        // Map polylines often repeat a point; zero-length segments have no direction, so drop them.
        var distinct: [Coordinate] = []
        for point in points where point != distinct.last {
            distinct.append(point)
        }
        guard distinct.count >= 2 else { throw .tooFewPoints }
        guard expectedTravelTime >= 0 else { throw .negativeTravelTime }

        var segments: [RouteSegment] = []
        var distanceSoFar = 0.0
        for (index, pair) in zip(distinct, distinct.dropFirst()).enumerated() {
            let segment = RouteSegment(index: index, start: pair.0, end: pair.1, distanceFromStart: distanceSoFar)
            segments.append(segment)
            distanceSoFar += segment.length
        }

        self.name = name
        self.points = distinct
        self.expectedTravelTime = expectedTravelTime
        self.segments = segments
    }

    /// Where `point` falls on the route, searching only `segmentRange` (all segments by default).
    /// - Complexity: O(*n*), where *n* is the number of segments searched.
    public func projection(of point: Coordinate, in segmentRange: Range<Int>? = nil) -> RouteProjection {
        let range = (segmentRange ?? segments.indices).clamped(to: segments.indices)
        var best: RouteProjection?
        for segment in segments[range] {
            let (along, away) = segment.project(point)
            if best == nil || away < (best?.distanceFromRoute ?? .infinity) {
                best = RouteProjection(
                    segmentIndex: segment.index,
                    distanceAlongRoute: segment.distanceFromStart + along,
                    distanceFromRoute: away,
                    routeBearing: segment.bearing,
                )
            }
        }
        // An empty search range falls back to the start of the route.
        return best ?? RouteProjection(
            segmentIndex: 0,
            distanceAlongRoute: 0,
            distanceFromRoute: segments[0].start.distance(to: point),
            routeBearing: segments[0].bearing,
        )
    }
}

/// Decoding goes through the validating initializer, so stored data can't break invariants.
extension Route: Codable {
    private enum CodingKeys: String, CodingKey {
        case name, points, expectedTravelTime
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            name: container.decode(String.self, forKey: .name),
            points: container.decode([Coordinate].self, forKey: .points),
            expectedTravelTime: container.decode(TimeInterval.self, forKey: .expectedTravelTime),
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(points, forKey: .points)
        try container.encode(expectedTravelTime, forKey: .expectedTravelTime)
    }
}
