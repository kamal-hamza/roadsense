import Presentation
import SwiftUI

@main
struct RoadSenseApp: App {
    /// Built once at launch and passed down; there are no global singletons.
    private let dependencies = AppContainer.makeLive()

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
    }
}
