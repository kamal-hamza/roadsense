import DriveSimulation
import Foundation
import SensorCore
import Testing

struct PathFollowingTests {
    private let start = Coordinate(latitude: 47.6, longitude: -122.3)

    /// A point `north` and `east` meters from the start.
    private func point(north: Double, east: Double = 0) -> Coordinate {
        Coordinate(
            latitude: start.latitude + north / 111_320,
            longitude: start.longitude + east / (111_320 * cos(start.latitude * .pi / 180)),
        )
    }

    /// Meters from `coordinate` to the nearest point on the polyline `path`.
    private func distance(from coordinate: Coordinate, toPath path: [Coordinate]) -> Double {
        zip(path, path.dropFirst()).map { segmentStart, segmentEnd in
            // Flat local frame around the segment start; fine over a few hundred meters.
            let scale = cos(segmentStart.latitude * .pi / 180)
            let endX = (segmentEnd.longitude - segmentStart.longitude) * 111_320 * scale
            let endY = (segmentEnd.latitude - segmentStart.latitude) * 111_320
            let pointX = (coordinate.longitude - segmentStart.longitude) * 111_320 * scale
            let pointY = (coordinate.latitude - segmentStart.latitude) * 111_320
            let fraction = min(1, max(0, (pointX * endX + pointY * endY) / (endX * endX + endY * endY)))
            return hypot(pointX - fraction * endX, pointY - fraction * endY)
        }.min() ?? .infinity
    }

    @Test func `drives an L-shaped path and stops at its end`() {
        let path = [point(north: 0), point(north: 600), point(north: 600, east: 400)]
        let drive = SyntheticDrive(segments: [.followPath(path, cruiseSpeed: 13)], startCoordinate: start)

        let fixes = drive.readings().compactMap { reading -> LocationSample? in
            if case let .location(fix) = reading {
                fix
            } else {
                nil
            }
        }

        let last = fixes.last
        #expect(fixes.count > 60)
        // It slows for the right-angle corner, so it should stay within a lane's width of the path.
        #expect(fixes.allSatisfy { distance(from: $0.coordinate, toPath: path) < 5 })
        #expect((last?.coordinate.distance(to: path[2]) ?? .infinity) < 10)
        #expect((last?.speed ?? .infinity) < 1)
        #expect((fixes.compactMap(\.speed).max() ?? 0) > 11)
    }

    @Test func `heads east on the second leg`() throws {
        let path = [point(north: 0), point(north: 300), point(north: 300, east: 600)]
        let drive = SyntheticDrive(segments: [.followPath(path, cruiseSpeed: 13)], startCoordinate: start)

        let eastbound = drive.readings().compactMap { reading -> LocationSample? in
            guard case let .location(fix) = reading, fix.coordinate.longitude > point(north: 0, east: 300).longitude
            else { return nil }
            return fix
        }

        let midLeg = try #require(eastbound.first)
        #expect(abs((midLeg.course ?? 0) - 90) < 15)
    }
}
