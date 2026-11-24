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
        let deviceIdentity = KeychainDeviceIdentityStore()
        let backend = makeBackend(deviceIdentity: deviceIdentity)
        let findRouteHotspots = FindRouteHotspotsUseCase(service: backend.hotspots, cache: FileHotspotCache())
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
            uploadPendingEvents: UploadPendingEventsUseCase(
                tripLogStore: tripLogStore,
                queue: FileUploadQueue(),
                uploader: backend.uploader,
                deviceIdentity: deviceIdentity,
                preferences: preferences,
            ),
            manageServerAddress: ManageServerAddressUseCase(store: UserDefaultsServerAddressStore()),
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

    /// The RoadSense server when one is configured (Debug: the dev server on this Mac), otherwise demo data.
    private static func makeBackend(
        deviceIdentity: any DeviceIdentityStore,
    ) -> (hotspots: any HotspotService, uploader: any EventUploader) {
        guard let baseURL = apiBaseURL, !isBackendOffline else {
            return (DemoHotspotService(isOffline: isBackendOffline), DemoEventUploader(isOffline: isBackendOffline))
        }
        let client = APIClient(baseURL: baseURL)
        return (HTTPHotspotService(client: client, deviceIdentity: deviceIdentity), HTTPEventUploader(client: client))
    }

    /// The server to use. Debug builds: `-demoBackend` means none, then the address saved in Settings or passed as
    /// `-apiBaseURL`. Otherwise the ROADSENSE_API_BASE_URL build setting (via Info.plist).
    private static var apiBaseURL: URL? {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-demoBackend") {
                return nil
            }
            if let override = UserDefaultsServerAddressStore().current {
                return override
            }
        #endif
        guard let text = Bundle.main.object(forInfoDictionaryKey: "RSAPIBaseURL") as? String, !text.isEmpty else {
            return nil
        }
        return URL(string: text)
    }

    /// Debug-only switch that makes the backend act unreachable (using the demo services), to try the offline paths.
    private static var isBackendOffline: Bool {
        #if DEBUG
            ProcessInfo.processInfo.arguments.contains("-backendOffline")
        #else
            false
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
