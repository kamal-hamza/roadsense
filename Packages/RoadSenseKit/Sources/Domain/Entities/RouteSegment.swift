import Foundation
import SensorCore

/// One straight piece of a route, between two consecutive route points.
public struct RouteSegment: Hashable, Sendable {
    public let index: Int
    public let start: Coordinate
    public let end: Coordinate
    /// Direction of travel along this segment.
    public let bearing: Bearing
    /// Length in meters.
    public let length: Double
    /// Distance along the route to `start`, in meters.
    public let distanceFromStart: Double

    init(index: Int, start: Coordinate, end: Coordinate, distanceFromStart: Double) {
        self.index = index
        self.start = start
        self.end = end
        bearing = start.bearing(to: end)
        length = start.distance(to: end)
        self.distanceFromStart = distanceFromStart
    }

    /// The closest point on this segment to `point`: how far along the segment it is, and how far away.
    func project(_ point: Coordinate) -> (distanceAlong: Double, distanceAway: Double) {
        let endOffset = end.localOffset(from: start)
        let pointOffset = point.localOffset(from: start)
        let lengthSquared = endOffset.x * endOffset.x + endOffset.y * endOffset.y
        guard lengthSquared > 0 else {
            return (0, start.distance(to: point))
        }
        // Dot product gives the fraction along the segment; clamp so we stay between the endpoints.
        let fraction = min(1, max(0, (pointOffset.x * endOffset.x + pointOffset.y * endOffset.y) / lengthSquared))
        let offsetX = pointOffset.x - fraction * endOffset.x
        let offsetY = pointOffset.y - fraction * endOffset.y
        return (fraction * length, (offsetX * offsetX + offsetY * offsetY).squareRoot())
    }
}
