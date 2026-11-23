import Application
import Domain
import SensorCore
import SensorRecording
import SwiftUI

/// Starts and stops trip recording, and shows live sensor readings for testing.
struct RecordingView: View {
    @State private var viewModel: RecordingViewModel

    init(recordTrip: RecordTripUseCase) {
        // @State keeps the view model alive across SwiftUI redraws of this struct.
        _viewModel = State(initialValue: RecordingViewModel(recordTrip: recordTrip))
    }

    var body: some View {
        List {
            Section {
                Label(
                    "For testing with a passenger. Don't look at this screen while driving.",
                    systemImage: "exclamationmark.triangle",
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            // Live data only appears once the first snapshot arrives.
            if viewModel.phase == .recording, let snapshot = viewModel.snapshot {
                LiveReadingsSection(snapshot: snapshot, chartPoints: viewModel.chartPoints)
                eventsSection(snapshot.events)
            }

            controlsSection

            if let trip = viewModel.lastSavedTrip {
                Section("Last Trip") {
                    LabeledContent(trip.name) {
                        // inflect: true picks "event" or "events" automatically.
                        Text("^[\(trip.events.count) event](inflect: true)")
                    }
                }
            }
        }
        .navigationTitle("Record")
        #if DEBUG
            // Dev hook for automated screenshots: launch with `-autoStartRecording`.
            .task {
                if ProcessInfo.processInfo.arguments.contains("-autoStartRecording") {
                    await viewModel.start()
                }
            }
        #endif
    }

    private var controlsSection: some View {
        Section {
            switch viewModel.phase {
            case .idle, .failed:
                Toggle("Save raw sensor log", isOn: $viewModel.logsRawSensors)
                Button("Start Recording", systemImage: "record.circle") {
                    // Button actions are synchronous, so start the async work in a Task.
                    Task { await viewModel.start() }
                }
                .font(.headline)
            case .recording:
                Button("Stop and Save", systemImage: "stop.circle", role: .destructive) {
                    Task { await viewModel.stop() }
                }
                .font(.headline)
            case .starting, .saving:
                ProgressView()
            }
        } footer: {
            if case let .failed(message) = viewModel.phase {
                Text(message).foregroundStyle(.red)
            }
        }
    }

    private func eventsSection(_ events: [DrivingEvent]) -> some View {
        Section("Events") {
            if events.isEmpty {
                Text("None yet")
                    .foregroundStyle(.secondary)
            }
            // Newest first.
            ForEach(events.reversed()) { event in
                EventRow(event: event)
            }
        }
    }
}

/// Speed, distance, phone alignment, and the live acceleration chart.
private struct LiveReadingsSection: View {
    let snapshot: RecordingSnapshot
    let chartPoints: [RecordingViewModel.ChartPoint]

    var body: some View {
        Section("Live") {
            LabeledContent("Elapsed") {
                // SwiftUI ticks this every second on its own; no timer code needed.
                Text(snapshot.startedAt, style: .timer)
                    .monospacedDigit()
            }
            LabeledContent("Speed") {
                if let speed = snapshot.speed {
                    Text(Measurement(value: speed, unit: UnitSpeed.metersPerSecond), format: .speed)
                } else {
                    Text("No GPS")
                }
            }
            LabeledContent("Distance") {
                Text(
                    Measurement(value: snapshot.distanceMeters, unit: UnitLength.meters),
                    format: .measurement(width: .abbreviated, usage: .road),
                )
            }
            LabeledContent("Phone alignment") {
                Text(snapshot.isFrameReady ? "Locked" : "Learning…")
                Text(snapshot.frameConfidence, format: .percent.precision(.fractionLength(0)))
                    .foregroundStyle(.secondary)
            }
            if let activity = snapshot.activity {
                LabeledContent("Activity", value: activity.kinds.map(\.rawValue).sorted().joined(separator: ", "))
            }
            if let status = snapshot.locationStatus {
                Label(status.message, systemImage: "location.slash")
                    .foregroundStyle(.orange)
            }
            if snapshot.motion?.isPhoneSettled == false {
                Label("Phone moving: events paused", systemImage: "iphone.radiowaves.left.and.right")
                    .foregroundStyle(.orange)
            }
            SignalChart(points: chartPoints)
        }
    }
}

private extension LocationStatus {
    var message: LocalizedStringKey {
        switch self {
        case .requestingAuthorization: "Waiting for location permission"
        case .denied: "Location access denied. Enable it in Settings."
        case .restricted: "Location access is restricted on this device"
        case .accuracyLimited: "Precise location is off. Enable it in Settings."
        case .needsForeground: "Open the app to resume location"
        case .unavailable: "Location unavailable"
        case .stationary: "Stationary"
        }
    }
}

#Preview {
    NavigationStack {
        RecordingView(recordTrip: AppDependencies.preview.recordTrip)
    }
}
