import Application
import SwiftUI

/// App settings: warnings, data sharing, and debug tools.
struct SettingsView: View {
    let recordTrip: RecordTripUseCase

    @State private var viewModel: SettingsViewModel
    @State private var showsRecording = false

    init(recordTrip: RecordTripUseCase, managePreferences: ManagePreferencesUseCase) {
        self.recordTrip = recordTrip
        _viewModel = State(initialValue: SettingsViewModel(managePreferences: managePreferences))
    }

    var body: some View {
        Form {
            Section {
                Toggle("Hazard Warnings", isOn: binding(\.warningsEnabled, set: viewModel.setWarningsEnabled))
            } footer: {
                Text("When off, drives start muted. You can still unmute during a drive.")
            }
            Section {
                Toggle("Share Trip Data", isOn: binding(\.dataSharingEnabled, set: viewModel.setDataSharingEnabled))
            } header: {
                Text("Privacy")
            } footer: {
                Text("""
                Shares hard brakes and hotspot passes so hotspots improve for everyone. Your routes and the areas \
                where trips start and end are never shared. When off, only anonymous counts are sent.
                """)
            }
            Section("Debug") {
                Button {
                    showsRecording = true
                } label: {
                    Label("Sensor Recording", systemImage: "waveform.path.ecg")
                }
            }
        }
        .disabled(!viewModel.isLoaded)
        .navigationTitle("Settings")
        .task { await viewModel.load() }
        .navigationDestination(isPresented: $showsRecording) {
            RecordingView(recordTrip: recordTrip)
        }
        #if DEBUG
        // `-autoStartRecording` opens the recording screen straight away (see RootView).
        .task {
            if ProcessInfo.processInfo.arguments.contains("-autoStartRecording") {
                showsRecording = true
            }
        }
        #endif
    }

    /// A toggle binding that reads from the view model and saves through `set`.
    private func binding(
        _ keyPath: KeyPath<AppPreferences, Bool>,
        set: @escaping (Bool) async -> Void,
    ) -> Binding<Bool> {
        Binding(
            get: { viewModel.preferences[keyPath: keyPath] },
            set: { newValue in Task { await set(newValue) } },
        )
    }
}

#Preview {
    NavigationStack {
        SettingsView(
            recordTrip: AppDependencies.preview.recordTrip,
            managePreferences: AppDependencies.preview.managePreferences,
        )
    }
}
