import Foundation
import SensorCore
import SensorRecording

/// Always authorized, always at one spot. Used in the iOS Simulator, which may have no location set.
public struct SimulatedLocationServices: LocationServices {
    public let coordinate: Coordinate

    /// Defaults to downtown Seattle, where `SyntheticDrive` starts.
    public init(coordinate: Coordinate = Coordinate(latitude: 47.6062, longitude: -122.3321)) {
        self.coordinate = coordinate
    }

    public func authorization() async -> LocationAuthorization {
        .authorized
    }

    public func requestAuthorization() async -> LocationAuthorization {
        .authorized
    }

    public func currentLocation() async throws -> LocationSample {
        LocationSample(
            timestamp: Date(),
            coordinate: coordinate,
            horizontalAccuracy: 5,
            speed: 0,
            speedAccuracy: 1,
            course: nil,
            courseAccuracy: nil,
        )
    }
}
