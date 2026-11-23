import Application

/// The use cases the Presentation layer needs, supplied by the composition root.
public struct AppDependencies: Sendable {
    public let listTrips: ListTripsUseCase
    public let recordTrip: RecordTripUseCase
    public let findSensorLog: FindSensorLogUseCase
    public let checkLocationAccess: CheckLocationAccessUseCase
    public let searchPlaces: SearchPlacesUseCase
    public let planRoute: PlanRouteUseCase
    public let findRouteHotspots: FindRouteHotspotsUseCase
    public let driveTrip: DriveTripUseCase
    public let recoverIncompleteTrip: RecoverIncompleteTripUseCase
    public let submitTripFeedback: SubmitTripFeedbackUseCase
    public let managePreferences: ManagePreferencesUseCase
    public let uploadPendingEvents: UploadPendingEventsUseCase

    public init(
        listTrips: ListTripsUseCase,
        recordTrip: RecordTripUseCase,
        findSensorLog: FindSensorLogUseCase,
        checkLocationAccess: CheckLocationAccessUseCase,
        searchPlaces: SearchPlacesUseCase,
        planRoute: PlanRouteUseCase,
        findRouteHotspots: FindRouteHotspotsUseCase,
        driveTrip: DriveTripUseCase,
        recoverIncompleteTrip: RecoverIncompleteTripUseCase,
        submitTripFeedback: SubmitTripFeedbackUseCase,
        managePreferences: ManagePreferencesUseCase,
        uploadPendingEvents: UploadPendingEventsUseCase,
    ) {
        self.listTrips = listTrips
        self.recordTrip = recordTrip
        self.findSensorLog = findSensorLog
        self.checkLocationAccess = checkLocationAccess
        self.searchPlaces = searchPlaces
        self.planRoute = planRoute
        self.findRouteHotspots = findRouteHotspots
        self.driveTrip = driveTrip
        self.recoverIncompleteTrip = recoverIncompleteTrip
        self.submitTripFeedback = submitTripFeedback
        self.managePreferences = managePreferences
        self.uploadPendingEvents = uploadPendingEvents
    }
}
