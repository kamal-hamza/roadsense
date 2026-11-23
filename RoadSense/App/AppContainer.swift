import Application
import Foundation
import Infrastructure
import Presentation
import SensorDevice
import SensorRecording

/// Composition root (like `Program.cs`): the only code that creates concrete types.
enum AppContainer {
    static func makeLive() -> AppDependencies {
        let tripRepository = FileTripRepository()
        let sensorLogStore = FileSensorLogStore()
        let recorder = SensorRecorder(sensorSource: makeSensorSource(), sensorLogStore: sensorLogStore)
        let locationServices = makeLocationServices()

        return AppDependencies(
            listTrips: ListTripsUseCase(repository: tripRepository),
            recordTrip: RecordTripUseCase(recorder: recorder, tripRepository: tripRepository),
            findSensorLog: FindSensorLogUseCase(store: sensorLogStore),
            checkLocationAccess: CheckLocationAccessUseCase(locationServices: locationServices),
            searchPlaces: SearchPlacesUseCase(locationServices: locationServices, placeSearch: MapKitPlaceSearch()),
            planRoute: PlanRouteUseCase(locationServices: locationServices, directions: MapKitDirections()),
            findRouteHotspots: FindRouteHotspotsUseCase(service: makeHotspotService(), cache: FileHotspotCache()),
        )
    }

    /// Demo hotspots until the Rust server exists (M6). `-hotspotServiceOffline` simulates no connection.
    private static func makeHotspotService() -> any HotspotService {
        #if DEBUG
            DemoHotspotService(isOffline: ProcessInfo.processInfo.arguments.contains("-hotspotServiceOffline"))
        #else
            DemoHotspotService()
        #endif
    }

    /// Real sensors on a phone; a simulated drive in the iOS Simulator, which has no motion sensors.
    private static func makeSensorSource() -> any SensorSource {
        #if targetEnvironment(simulator)
            SimulatedSensorSource()
        #else
            LiveSensorSource()
        #endif
    }

    /// Real location on a phone; a fixed spot in the Simulator, which often has no location set.
    private static func makeLocationServices() -> any LocationServices {
        #if targetEnvironment(simulator)
            SimulatedLocationServices()
        #else
            LiveLocationServices()
        #endif
    }
}
