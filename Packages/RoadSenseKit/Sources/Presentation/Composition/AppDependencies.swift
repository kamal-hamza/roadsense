import Application

/// The use cases the Presentation layer needs, supplied by the composition root.
public struct AppDependencies: Sendable {
    public let listTrips: ListTripsUseCase
    public let recordTrip: RecordTripUseCase
    public let findSensorLog: FindSensorLogUseCase
    public let checkLocationAccess: CheckLocationAccessUseCase
    public let searchPlaces: SearchPlacesUseCase
    public let planRoute: PlanRouteUseCase

    public init(
        listTrips: ListTripsUseCase,
        recordTrip: RecordTripUseCase,
        findSensorLog: FindSensorLogUseCase,
        checkLocationAccess: CheckLocationAccessUseCase,
        searchPlaces: SearchPlacesUseCase,
        planRoute: PlanRouteUseCase,
    ) {
        self.listTrips = listTrips
        self.recordTrip = recordTrip
        self.findSensorLog = findSensorLog
        self.checkLocationAccess = checkLocationAccess
        self.searchPlaces = searchPlaces
        self.planRoute = planRoute
    }
}
