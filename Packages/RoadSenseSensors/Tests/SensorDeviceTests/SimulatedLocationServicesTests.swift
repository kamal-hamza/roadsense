import Foundation
import SensorCore
import SensorDevice
import SensorRecording
import Testing

struct SimulatedLocationServicesTests {
    @Test func `is authorized without prompting and reports its fixed spot`() async throws {
        let spot = Coordinate(latitude: 40.7, longitude: -74)
        let services = SimulatedLocationServices(coordinate: spot)

        let status = await services.authorization()
        let requested = await services.requestAuthorization()
        let fix = try await services.currentLocation()

        #expect(status == .authorized)
        #expect(requested == .authorized)
        #expect(fix.coordinate == spot)
        #expect(fix.horizontalAccuracy <= 30)
    }
}
