import SwiftUI

/// The app's root view. Entry point from the composition root into Presentation.
public struct RootView: View {
    private let dependencies: AppDependencies

    public init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    public var body: some View {
        NavigationStack {
            TripListView(listTrips: dependencies.listTrips)
        }
    }
}

#Preview {
    RootView(dependencies: .preview)
}
