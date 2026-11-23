import Foundation
import SensorCore

/// A path on a flat local map (meters east/north of its first point), for steering a synthetic car along it.
struct PathGeometry {
    private let origin: Coordinate
    private let metersPerDegreeLongitude: Double
    /// Path points in local meters.
    private let points: [SIMD2<Double>]
    /// Distance from the start to each point.
    private let distances: [Double]

    var length: Double {
        distances.last ?? 0
    }

    init(_ path: [Coordinate]) {
        origin = path[0]
        // ~111 km per degree of latitude; longitude degrees shrink with cos(latitude).
        metersPerDegreeLongitude = 111_320 * cos(path[0].latitude * .pi / 180)
        let local = path.map { coordinate in
            SIMD2(
                (coordinate.longitude - path[0].longitude) * 111_320 * cos(path[0].latitude * .pi / 180),
                (coordinate.latitude - path[0].latitude) * 111_320,
            )
        }
        points = local
        var running = 0.0
        distances = [0] + zip(local, local.dropFirst()).map { start, end in
            running += (end - start).length
            return running
        }
    }

    func local(_ coordinate: Coordinate) -> SIMD2<Double> {
        SIMD2(
            (coordinate.longitude - origin.longitude) * metersPerDegreeLongitude,
            (coordinate.latitude - origin.latitude) * 111_320,
        )
    }

    /// Distance along the path of the closest point to `position`, searching segments from `startSegment` on.
    /// Returns the segment it landed on too, so the next search can start there and never go backwards.
    func progress(of position: SIMD2<Double>, fromSegment startSegment: Int) -> (distance: Double, segment: Int) {
        var best = (distance: distances[startSegment], segment: startSegment, gap: Double.infinity)
        // Only look a few segments ahead: enough to pass short ones, not enough to jump to a far stretch.
        for index in startSegment ..< min(points.count - 1, startSegment + 8) {
            let start = points[index]
            let direction = points[index + 1] - start
            let lengthSquared = direction.lengthSquared
            let fraction = lengthSquared > 0 ? min(1, max(0, (position - start).dot(direction) / lengthSquared)) : 0
            let gap = (position - (start + fraction * direction)).length
            if gap < best.gap {
                best = (distances[index] + fraction * (distances[index + 1] - distances[index]), index, gap)
            }
        }
        return (best.distance, best.segment)
    }

    /// The local point `distance` meters along the path, clamped to its ends.
    func point(atDistance distance: Double) -> SIMD2<Double> {
        let clamped = min(max(0, distance), length)
        guard let index = distances.lastIndex(where: { $0 <= clamped }), index < points.count - 1 else {
            return points[points.count - 1]
        }
        let span = distances[index + 1] - distances[index]
        let fraction = span > 0 ? (clamped - distances[index]) / span : 0
        return points[index] + fraction * (points[index + 1] - points[index])
    }

    /// The sharpest turn (degrees) at any path corner between `distance` and `distance + window`, and how far away it
    /// is.
    func sharpestTurn(after distance: Double, within window: Double) -> (degrees: Double, distanceAway: Double)? {
        var sharpest: (degrees: Double, distanceAway: Double)?
        for index in 1 ..< max(1, points.count - 1) where distances[index] > distance {
            guard distances[index] <= distance + window else { break }
            let incoming = (points[index] - points[index - 1]).normalized
            let outgoing = (points[index + 1] - points[index]).normalized
            // Angle between the two directions; 0 is straight on, 90 a right angle.
            let degrees = acos(min(1, max(-1, incoming.dot(outgoing)))) * 180 / .pi
            if degrees > (sharpest?.degrees ?? 0) {
                sharpest = (degrees, distances[index] - distance)
            }
        }
        return sharpest
    }
}

/// Small 2D vector helpers; the simd module isn't available in this Foundation-only target.
private extension SIMD2 where Scalar == Double {
    func dot(_ other: Self) -> Double {
        x * other.x + y * other.y
    }

    var lengthSquared: Double {
        dot(self)
    }

    var length: Double {
        lengthSquared.squareRoot()
    }

    /// Unit vector in the same direction; zero stays zero.
    var normalized: Self {
        length > 0 ? self / length : self
    }
}
