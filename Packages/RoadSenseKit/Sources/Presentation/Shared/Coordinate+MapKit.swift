import MapKit
import SensorCore

extension CLLocationCoordinate2D {
    /// Converts a sensor-package coordinate for drawing on a SwiftUI `Map`.
    init(_ coordinate: Coordinate) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
