import Application
import Domain
import Foundation
import Observation

/// State and actions for `DriveView` (activity diagrams 3–5).
@Observable
final class DriveViewModel {
    enum State: Equatable {
        case starting
        case driving(DriveUpdate)
        case ended(TripLog)
        case failed
    }

    let plan: TripPlan
    private(set) var state: State = .starting

    @ObservationIgnored private let driveTrip: DriveTripUseCase

    init(plan: TripPlan, driveTrip: DriveTripUseCase) {
        self.plan = plan
        self.driveTrip = driveTrip
    }

    var isMuted: Bool {
        if case let .driving(update) = state {
            update.isMuted
        } else {
            false
        }
    }

    /// Starts the drive and follows it until it ends. Runs for the whole drive, so call it from `.task`.
    func run() async {
        do {
            for await driveState in try await driveTrip.start(plan) {
                switch driveState {
                case let .driving(update): state = .driving(update)
                case let .ended(log): state = .ended(log)
                }
            }
        } catch {
            state = .failed
        }
    }

    func toggleMute() async {
        await driveTrip.setMuted(!isMuted)
    }

    /// Ends the drive early; the final state arrives through `run()`.
    func end() async {
        await driveTrip.end()
    }
}
