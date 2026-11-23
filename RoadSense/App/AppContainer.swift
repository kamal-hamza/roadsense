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
        let recordTrip = RecordTripUseCase(recorder: recorder, tripRepository: tripRepository)
        let directions = MapKitDirections()
        let findRouteHotspots = FindRouteHotspotsUseCase(service: makeHotspotService(), cache: FileHotspotCache())
        let tripLogStore = FileTripLogStore()
        let preferences = UserDefaultsPreferences()

        return AppDependencies(
            listTrips: ListTripsUseCase(repository: tripRepository),
            recordTrip: recordTrip,
            findSensorLog: FindSensorLogUseCase(store: sensorLogStore),
            checkLocationAccess: CheckLocationAccessUseCase(locationServices: locationServices),
            searchPlaces: SearchPlacesUseCase(locationServices: locationServices, placeSearch: MapKitPlaceSearch()),
            planRoute: PlanRouteUseCase(locationServices: locationServices, directions: directions),
            findRouteHotspots: findRouteHotspots,
            driveTrip: DriveTripUseCase(
                recordTrip: recordTrip,
                tripLogStore: tripLogStore,
                alerting: makeAlerter(),
                directions: directions,
                findHotspots: findRouteHotspots,
                preferences: preferences,
            ),
            recoverIncompleteTrip: RecoverIncompleteTripUseCase(tripLogStore: tripLogStore),
            submitTripFeedback: SubmitTripFeedbackUseCase(tripLogStore: tripLogStore),
            managePreferences: ManagePreferencesUseCase(preferences: preferences),
        )
    }

    /// `-skipNotificationPrompt` (debug only) lets automated runs start a drive without answering the prompt.
    private static func makeAlerter() -> any DriveAlerting {
        #if DEBUG
            SystemDriveAlerter(
                asksForNotificationPermission: !ProcessInfo.processInfo.arguments.contains("-skipNotificationPrompt"),
            )
        #else
            SystemDriveAlerter()
        #endif
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
