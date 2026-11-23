import Application
import SwiftUI

/// App settings. For now only the debug tools; warning and data-sharing switches come with the drive.
struct SettingsView: View {
    let recordTrip: RecordTripUseCase

    @State private var showsRecording = false

    var body: some View {
        Form {
            Section("Debug") {
                Button {
                    showsRecording = true
                } label: {
                    Label("Sensor Recording", systemImage: "waveform.path.ecg")
                }
            }
        }
        .navigationTitle("Settings")
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
}

#Preview {
    NavigationStack {
        SettingsView(recordTrip: AppDependencies.preview.recordTrip)
    }
}
