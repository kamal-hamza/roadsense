import Application

/// The use cases the Presentation layer needs, supplied by the composition root.
public struct AppDependencies: Sendable {
    public let listTrips: ListTripsUseCase
    public let recordTrip: RecordTripUseCase
    public let findSensorLog: FindSensorLogUseCase

    public init(listTrips: ListTripsUseCase, recordTrip: RecordTripUseCase, findSensorLog: FindSensorLogUseCase) {
        self.listTrips = listTrips
        self.recordTrip = recordTrip
        self.findSensorLog = findSensorLog
    }
}
