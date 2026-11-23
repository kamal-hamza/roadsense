import Application
import Domain
import SwiftUI

/// After the drive: what happened, and whether the warnings helped.
struct TripSummaryView: View {
    @State private var viewModel: TripSummaryViewModel
    private let onDone: () -> Void

    init(log: TripLog, plan: TripPlan, submitFeedback: SubmitTripFeedbackUseCase, onDone: @escaping () -> Void) {
        _viewModel = State(initialValue: TripSummaryViewModel(log: log, plan: plan, submitFeedback: submitFeedback))
        self.onDone = onDone
    }

    var body: some View {
        List {
            Section {
                Label("Drive Complete", systemImage: "flag.checkered")
                    .font(.title2.bold())
            }
            Section("This Drive") {
                LabeledContent("Hotspots passed", value: viewModel.summary.hotspotsPassed, format: .number)
                LabeledContent("Warnings given", value: viewModel.summary.warningsGiven, format: .number)
                LabeledContent(
                    "Hard brakes near hotspots",
                    value: viewModel.summary.hardBrakesNearHotspots,
                    format: .number,
                )
            }
            FeedbackSection(viewModel: viewModel)
        }
        .safeAreaInset(edge: .bottom) {
            // Done without answering counts as dismissing the question.
            Button(action: onDone) {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
        }
    }
}

/// "Were the warnings helpful?" and its follow-ups.
private struct FeedbackSection: View {
    let viewModel: TripSummaryViewModel

    var body: some View {
        switch viewModel.feedbackStep {
        case .notAsked:
            EmptyView()
        case .asking:
            Section("Were the warnings helpful?") {
                HStack(spacing: 12) {
                    Button {
                        Task { await viewModel.answerHelpful() }
                    } label: {
                        Label("Helpful", systemImage: "hand.thumbsup.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    Button {
                        Task { await viewModel.answerNotHelpful() }
                    } label: {
                        Label("Not Helpful", systemImage: "hand.thumbsdown.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .buttonStyle(.bordered)
            }
        case .pickingWarning:
            Section("Which warning wasn't useful?") {
                ForEach(viewModel.warnedHotspots) { hotspot in
                    Button {
                        Task { await viewModel.pick(hotspot) }
                    } label: {
                        HotspotRow(routeHotspot: hotspot)
                    }
                    .tint(.primary)
                }
                Button("Never Mind", role: .cancel) { viewModel.cancelPicking() }
            }
        case .thanks:
            Section {
                Label("Thanks, that helps other drivers.", systemImage: "checkmark.circle.fill")
            }
        case .saveFailed:
            Section {
                Label("Couldn't save your feedback.", systemImage: "exclamationmark.triangle")
            }
        }
    }
}

#Preview("With warnings") {
    TripSummaryView(
        log: .previewFinished,
        plan: .preview,
        submitFeedback: AppDependencies.preview.submitTripFeedback,
    ) {}
}
