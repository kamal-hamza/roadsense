import Application
import Domain
import SwiftUI

/// A recorded trip's summary, its detected events, and its raw sensor log.
struct TripDetailView: View {
    @State private var viewModel: TripDetailViewModel

    init(trip: Trip, findSensorLog: FindSensorLogUseCase) {
        _viewModel = State(initialValue: TripDetailViewModel(trip: trip, findSensorLog: findSensorLog))
    }

    var body: some View {
        let trip = viewModel.trip
        List {
            Section("Summary") {
                LabeledContent("Started") {
                    Text(trip.startedAt, format: .dateTime.month().day().hour().minute())
                }
                if let endedAt = trip.endedAt {
                    LabeledContent("Duration") {
                        Text(
                            Duration.seconds(endedAt.timeIntervalSince(trip.startedAt)),
                            format: .time(pattern: .hourMinuteSecond),
                        )
                    }
                }
                LabeledContent("Distance") {
                    Text(trip.distance, format: .measurement(width: .abbreviated, usage: .road))
                }
            }

            Section("Events") {
                if trip.events.isEmpty {
                    Text("No events detected")
                        .foregroundStyle(.secondary)
                }
                ForEach(trip.events) { event in
                    EventRow(event: event)
                }
            }

            if let url = viewModel.sensorLogURL {
                Section {
                    ShareLink(item: url) {
                        Label("Export Raw Sensor Log", systemImage: "square.and.arrow.up")
                    }
                } footer: {
                    Text("JSON Lines, one reading per line. Use it to replay this drive in tests.")
                }
            }
        }
        .navigationTitle(trip.name)
        // iOS-only modifier; the guard keeps the package building on macOS for editor tooling.
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .task { await viewModel.load() }
    }
}

#Preview {
    NavigationStack {
        if let trip = Trip.previewSamples.first {
            TripDetailView(trip: trip, findSensorLog: AppDependencies.preview.findSensorLog)
        }
    }
}
