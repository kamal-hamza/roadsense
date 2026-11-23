import Application
import Foundation
import SensorRecording

/// Why searching or routing failed, in terms the screens can explain to the driver.
enum PlanningFailure: Equatable {
    case locationNotAuthorized
    case locationUnavailable
    case mapsUnavailable
    case throttled

    init(_ error: any Error) {
        switch error {
        case LocationServicesError.notAuthorized: self = .locationNotAuthorized
        case LocationServicesError.unavailable: self = .locationUnavailable
        case MapServiceError.throttled: self = .throttled
        default: self = .mapsUnavailable
        }
    }
}
