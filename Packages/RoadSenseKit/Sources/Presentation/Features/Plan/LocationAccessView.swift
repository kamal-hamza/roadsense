import Application
import SensorRecording
import SwiftUI

#if os(iOS)
    import UIKit
#endif

/// Explains why RoadSense needs location, and asks for it or points to Settings.
struct LocationAccessView: View {
    let viewModel: LocationAccessViewModel

    @Environment(\.openURL) private var openURL

    var body: some View {
        switch viewModel.state {
        case .checking, .granted:
            ProgressView()
        case .needsPermission:
            ContentUnavailableView {
                Label("Warnings Need Your Location", systemImage: "location.fill")
            } description: {
                Text("RoadSense uses your location to plan your route and warn you before hazards ahead.")
            } actions: {
                Button("Allow Location") {
                    Task { await viewModel.requestAccess() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        case .denied:
            ContentUnavailableView {
                Label("Location Is Off", systemImage: "location.slash")
            } description: {
                Text("RoadSense can't plan a route or warn you without your location. Turn it on in Settings.")
            } actions: {
                #if os(iOS)
                    if let settings = URL(string: UIApplication.openSettingsURLString) {
                        Button("Open Settings") { openURL(settings) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                #endif
            }
        case .restricted:
            ContentUnavailableView(
                "Location Is Restricted",
                systemImage: "lock.fill",
                description: Text("Location access is blocked on this device, so RoadSense can't plan or warn."),
            )
        }
    }
}

#Preview("Needs permission") {
    let viewModel = LocationAccessViewModel(checkAccess: .preview(.notDetermined))
    LocationAccessView(viewModel: viewModel)
        .task { await viewModel.check() }
}

#Preview("Denied") {
    let viewModel = LocationAccessViewModel(checkAccess: .preview(.denied))
    LocationAccessView(viewModel: viewModel)
        .task { await viewModel.check() }
}

#Preview("Restricted") {
    let viewModel = LocationAccessViewModel(checkAccess: .preview(.restricted))
    LocationAccessView(viewModel: viewModel)
        .task { await viewModel.check() }
}
