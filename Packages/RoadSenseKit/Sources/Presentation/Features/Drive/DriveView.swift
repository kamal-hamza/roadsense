import Application
import Domain
import SwiftUI

#if os(iOS)
    import UIKit
#endif

/// The screen during a drive: glanceable, with big targets and nothing to read closely.
struct DriveView: View {
    @State private var viewModel: DriveViewModel
    @State private var confirmsEnd = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let submitFeedback: SubmitTripFeedbackUseCase
    private let onDone: () -> Void

    init(
        plan: TripPlan,
        driveTrip: DriveTripUseCase,
        submitFeedback: SubmitTripFeedbackUseCase,
        onDone: @escaping () -> Void,
    ) {
        _viewModel = State(initialValue: DriveViewModel(plan: plan, driveTrip: driveTrip))
        self.submitFeedback = submitFeedback
        self.onDone = onDone
    }

    var body: some View {
        content
            .padding()
            .task { await viewModel.run() }
        #if os(iOS)
            // Keep the screen on while driving, like a navigation app; restore it when the drive screen goes.
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .starting:
            ProgressView("Starting drive…")
        case let .driving(update):
            VStack(spacing: 24) {
                WarningBanner(update: update)
                    .animation(reduceMotion ? nil : .snappy, value: update.activeWarning)
                Spacer()
                SpeedReadout(speed: update.speed)
                Spacer()
                controls(isMuted: update.isMuted)
            }
        case let .ended(log):
            TripSummaryView(log: log, plan: viewModel.plan, submitFeedback: submitFeedback, onDone: onDone)
        case .failed:
            ContentUnavailableView {
                Label("Couldn't Start the Drive", systemImage: "exclamationmark.triangle")
            } description: {
                Text("RoadSense couldn't start the sensors. Try again.")
            } actions: {
                Button("Close", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
    }

    private func controls(isMuted: Bool) -> some View {
        HStack(spacing: 16) {
            Button {
                Task { await viewModel.toggleMute() }
            } label: {
                Label(isMuted ? "Unmute" : "Mute", systemImage: isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                confirmsEnd = true
            } label: {
                Label("End Trip", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
            .buttonStyle(.borderedProminent)
            .confirmationDialog("End this trip?", isPresented: $confirmsEnd, titleVisibility: .visible) {
                Button("End Trip", role: .destructive) {
                    Task { await viewModel.end() }
                }
            }
        }
        .font(.title3.weight(.semibold))
    }
}

/// The current speed, large enough to read at a glance.
private struct SpeedReadout: View {
    let speed: Double?
    /// Grows with Dynamic Type like a text style, from a big glanceable base size.
    @ScaledMetric(relativeTo: .largeTitle) private var size = 64.0

    var body: some View {
        VStack(spacing: 4) {
            Text(speed.map(DriveFormat.speed) ?? "–")
                .font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.5)
            Text("Speed")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Drive") {
    DriveView(
        plan: .preview,
        driveTrip: AppDependencies.preview.driveTrip,
        submitFeedback: AppDependencies.preview.submitTripFeedback,
    ) {}
}
