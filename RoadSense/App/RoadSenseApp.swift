import Presentation
import SwiftUI

@main
struct RoadSenseApp: App {
    private let dependencies = AppContainer.makeLive()

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
    }
}
