import Application
import Domain
import Foundation
import SensorCore
import SensorRecording

// Preview-only fakes. Not `#if DEBUG` because Release builds type-check `#Preview` too.

struct PreviewTripRepository: TripRepository {
    var trips: [Trip]

    func allTrips() async throws -> [Trip] {
        trips
    }

    func save(_: Trip) async throws {}
}

/// A sensor source that never produces readings.
struct PreviewSensorSource: SensorSource {
    func readings(configuration _: SensorConfiguration) async -> AsyncStream<SensorReading> {
        AsyncStream { $0.finish() }
    }
}

struct PreviewSensorLogStore: SensorLogStore {
    func beginLog(recordingID _: UUID) async throws {}
    func append(_: [SensorReading]) async throws {}
    func finishLog() async throws {}
    func logURL(recordingID _: UUID) async -> URL? {
        nil
    }
}

/// Location that's always available at a fixed spot in Seattle, with a configurable permission.
struct PreviewLocationServices: LocationServices {
    var status: LocationAuthorization = .authorized

    func authorization() async -> LocationAuthorization {
        status
    }

    func requestAuthorization() async -> LocationAuthorization {
        .authorized
    }

    func currentLocation() async throws -> LocationSample {
        LocationSample(
            timestamp: .now,
            coordinate: Coordinate(latitude: 47.6062, longitude: -122.3321),
            horizontalAccuracy: 5,
            speed: nil,
            speedAccuracy: nil,
            course: nil,
            courseAccuracy: nil,
        )
    }
}

struct PreviewPlaceSearch: PlaceSearching {
    var places: [Place] = [.previewDestination]

    func places(matching _: String, near _: Coordinate) async throws -> [Place] {
        places
    }
}

struct PreviewDirections: DirectionsProviding {
    var routes: [Route] = Route.previewSamples

    func routes(from _: Coordinate, to _: Place) async throws -> [Route] {
        routes
    }
}

/// Hotspots spread along whatever route is asked for, or an unreachable backend.
struct PreviewHotspotService: HotspotService {
    var isAvailable = true

    func hotspots(along route: Route) async throws -> [RouteHotspot] {
        guard isAvailable else { throw HotspotServiceError.unavailable }
        let kinds: [HotspotKind] = [.sharpCurve, .suddenStop]
        return [0.35, 0.75].enumerated().map { index, fraction in
            let location = route.location(atDistance: route.length * fraction)
            let hotspot = Hotspot(
                id: UUID(),
                kind: kinds[index],
                coordinate: location.coordinate,
                bearing: location.bearing,
                driverCount: 6 + index * 5,
            )
            return RouteHotspot(hotspot: hotspot, distanceAlongRoute: route.length * fraction)
        }
    }
}

/// A trip log store that keeps nothing.
struct PreviewTripLogStore: TripLogStore {
    func begin(_: TripLog) async throws {}
    func append(_: TripLogEntry) async throws {}
    func finish(at _: Date, reason _: TripEndReason, endCoordinate _: Coordinate?) async throws {}
    func unfinishedLog() async throws -> TripLog? {
        nil
    }

    func finishedLogs() async throws -> [TripLog] {
        []
    }

    func saveFinished(_: TripLog) async throws {}
    func deleteFinished(id _: TripLog.ID) async throws {}
}

/// Alerts that stay silent in previews.
struct PreviewDriveAlerting: DriveAlerting {
    func prepare() async {}
    func announce(_: DriveWarning) async {}
}

/// An upload queue that's always empty.
struct PreviewUploadQueue: UploadQueue {
    func enqueue(_: UploadBatch) async throws {}
    func pending() async throws -> [UploadBatch] {
        []
    }

    func remove(id _: UploadBatch.ID) async throws {}
}

/// An uploader that accepts everything and sends nothing.
struct PreviewEventUploader: EventUploader {
    func upload(_: UploadBatch) async -> UploadResult {
        .accepted
    }

    func registerDevice(_: DeviceID) async throws {}
}

struct PreviewDeviceIdentity: DeviceIdentityStore {
    func deviceID() async throws -> DeviceID {
        DeviceID(rawValue: UUID())
    }
}

/// Settings kept in memory for previews.
actor PreviewPreferences: UserPreferences {
    private var stored = AppPreferences()

    func load() async -> AppPreferences {
        stored
    }

    func save(_ preferences: AppPreferences) async {
        stored = preferences
    }
}

/// A hotspot cache with nothing saved.
struct PreviewHotspotCache: HotspotCache {
    func save(_: CachedHotspotArea) async throws {}
    func areas() async throws -> [CachedHotspotArea] {
        []
    }
}

extension Place {
    nonisolated static let previewDestination = Place(
        name: "Pike Place Market",
        subtitle: "85 Pike St",
        coordinate: Coordinate(latitude: 47.6097, longitude: -122.3422),
    )
}

extension Route {
    nonisolated static let previewSamples: [Route] = [
        try? Route(
            name: "1st Ave",
            points: [
                Coordinate(latitude: 47.6062, longitude: -122.3321),
                Coordinate(latitude: 47.6040, longitude: -122.3355),
                Coordinate(latitude: 47.6097, longitude: -122.3422),
            ],
            expectedTravelTime: 420,
        ),
        try? Route(
            name: "3rd Ave",
            points: [
                Coordinate(latitude: 47.6062, longitude: -122.3321),
                Coordinate(latitude: 47.6100, longitude: -122.3360),
                Coordinate(latitude: 47.6097, longitude: -122.3422),
            ],
            expectedTravelTime: 540,
        ),
    ].compactMap(\.self)
}

extension TripPlan {
    nonisolated static let preview = TripPlan(
        destination: .previewDestination,
        route: Route.previewSamples[0],
        hotspots: [],
        freshness: .live,
    )
}

extension TripLog {
    /// A finished drive with two warnings and two passes, for the summary preview.
    nonisolated static var previewFinished: TripLog {
        var log = TripLog(startedAt: .now.addingTimeInterval(-600), startCoordinate: nil)
        let ids = [UUID(), UUID()]
        log.append(TripLogEntry(
            timestamp: .now.addingTimeInterval(-500),
            coordinate: nil,
            event: .warningShown(hotspotIDs: ids, speed: 14),
        ))
        for id in ids {
            log.append(TripLogEntry(
                timestamp: .now.addingTimeInterval(-480),
                coordinate: nil,
                event: .hotspotPassed(hotspotID: id, outcome: .warned(secondsOfWarning: 9), brakedHard: false),
            ))
        }
        try? log.finish(at: .now, reason: .arrived, endCoordinate: nil)
        return log
    }
}

extension CheckLocationAccessUseCase {
    static func preview(_ status: LocationAuthorization) -> CheckLocationAccessUseCase {
        CheckLocationAccessUseCase(locationServices: PreviewLocationServices(status: status))
    }
}

extension DrivingEvent {
    static let previewSamples: [DrivingEvent] = [
        DrivingEvent(
            kind: .hardBrake,
            timestamp: .now.addingTimeInterval(-3000),
            duration: 1.2,
            peakAcceleration: 0.47,
            speed: 17,
            course: 90,
            coordinate: Coordinate(latitude: 47.61, longitude: -122.33),
            confidence: 0.9,
        ),
        DrivingEvent(
            kind: .sharpTurn,
            timestamp: .now.addingTimeInterval(-2800),
            duration: 2.5,
            peakAcceleration: 0.41,
            speed: 12,
            course: 180,
            coordinate: Coordinate(latitude: 47.62, longitude: -122.34),
            confidence: 1,
        ),
    ]
}

extension Trip {
    static let previewSamples: [Trip] = [
        try? Trip(
            name: "Morning commute",
            startedAt: .now.addingTimeInterval(-3600),
            endedAt: .now.addingTimeInterval(-2400),
            distance: .init(value: 18.4, unit: .kilometers),
            events: DrivingEvent.previewSamples,
        ),
        try? Trip(
            name: "Weekend drive",
            startedAt: .now.addingTimeInterval(-86400 * 2),
            distance: .init(value: 112, unit: .kilometers),
        ),
    ].compactMap(\.self)
}

extension AppDependencies {
    static let preview = preview()

    static func preview(
        trips: [Trip] = Trip.previewSamples,
        authorization: LocationAuthorization = .authorized,
        routes: [Route] = Route.previewSamples,
        hotspotsAvailable: Bool = true,
    ) -> AppDependencies {
        let repository = PreviewTripRepository(trips: trips)
        let logStore = PreviewSensorLogStore()
        let locationServices = PreviewLocationServices(status: authorization)
        let recordTrip = RecordTripUseCase(
            recorder: SensorRecorder(sensorSource: PreviewSensorSource(), sensorLogStore: logStore),
            tripRepository: repository,
        )
        let findRouteHotspots = FindRouteHotspotsUseCase(
            service: PreviewHotspotService(isAvailable: hotspotsAvailable),
            cache: PreviewHotspotCache(),
            retryDelays: [],
        )
        let directions = PreviewDirections(routes: routes)
        let preferences = PreviewPreferences()
        return AppDependencies(
            listTrips: ListTripsUseCase(repository: repository),
            recordTrip: recordTrip,
            findSensorLog: FindSensorLogUseCase(store: logStore),
            checkLocationAccess: CheckLocationAccessUseCase(locationServices: locationServices),
            searchPlaces: SearchPlacesUseCase(locationServices: locationServices, placeSearch: PreviewPlaceSearch()),
            planRoute: PlanRouteUseCase(locationServices: locationServices, directions: directions),
            findRouteHotspots: findRouteHotspots,
            driveTrip: DriveTripUseCase(
                recordTrip: recordTrip,
                tripLogStore: PreviewTripLogStore(),
                alerting: PreviewDriveAlerting(),
                directions: directions,
                findHotspots: findRouteHotspots,
                preferences: preferences,
            ),
            recoverIncompleteTrip: RecoverIncompleteTripUseCase(tripLogStore: PreviewTripLogStore()),
            submitTripFeedback: SubmitTripFeedbackUseCase(tripLogStore: PreviewTripLogStore()),
            managePreferences: ManagePreferencesUseCase(preferences: preferences),
            uploadPendingEvents: UploadPendingEventsUseCase(
                tripLogStore: PreviewTripLogStore(),
                queue: PreviewUploadQueue(),
                uploader: PreviewEventUploader(),
                deviceIdentity: PreviewDeviceIdentity(),
                preferences: preferences,
            ),
        )
    }
}
