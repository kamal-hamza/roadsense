import Application
import Foundation
import Observation
import SensorRecording

/// State and actions for `LocationAccessView` (activity diagram 1, permission branch).
@Observable
final class LocationAccessViewModel {
    enum State: Equatable {
        case checking
        case needsPermission
        case denied
        case restricted
        case granted
    }

    private(set) var state: State = .checking

    @ObservationIgnored private let checkAccess: CheckLocationAccessUseCase

    init(checkAccess: CheckLocationAccessUseCase) {
        self.checkAccess = checkAccess
    }

    /// Re-reads the permission, e.g. when the driver comes back from Settings.
    func check() async {
        state = await State(checkAccess())
    }

    /// Shows the system prompt (only works while the driver hasn't been asked yet).
    func requestAccess() async {
        state = await State(checkAccess.request())
    }
}

private extension LocationAccessViewModel.State {
    init(_ authorization: LocationAuthorization) {
        switch authorization {
        case .notDetermined: self = .needsPermission
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .authorized: self = .granted
        }
    }
}
