import SwiftUI

/// Explains a failed search or route request in words the driver can act on.
struct PlanningFailureView: View {
    let failure: PlanningFailure

    var body: some View {
        switch failure {
        case .locationNotAuthorized:
            ContentUnavailableView(
                "Location Is Off",
                systemImage: "location.slash",
                description: Text("Turn on location for RoadSense in Settings to plan a route."),
            )
        case .locationUnavailable:
            ContentUnavailableView(
                "Can't Find You",
                systemImage: "location.slash",
                description: Text("Your location isn't available right now. Try again in a moment."),
            )
        case .mapsUnavailable:
            ContentUnavailableView(
                "Maps Unavailable",
                systemImage: "wifi.exclamationmark",
                description: Text("Couldn't reach the map service. Check your connection and try again."),
            )
        case .throttled:
            ContentUnavailableView(
                "Too Many Searches",
                systemImage: "hourglass",
                description: Text("Wait a minute, then try again."),
            )
        }
    }
}
