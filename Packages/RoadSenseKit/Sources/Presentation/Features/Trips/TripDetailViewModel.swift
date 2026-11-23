import Application
import Domain
import Foundation
import Observation

/// State and actions for `TripDetailView`.
@Observable
final class TripDetailViewModel {
    let trip: Trip
    private(set) var sensorLogURL: URL?

    @ObservationIgnored private let findSensorLog: FindSensorLogUseCase

    init(trip: Trip, findSensorLog: FindSensorLogUseCase) {
        self.trip = trip
        self.findSensorLog = findSensorLog
    }

    func load() async {
        sensorLogURL = await findSensorLog(tripID: trip.id)
    }
}
