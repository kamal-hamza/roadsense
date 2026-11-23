import Application
import Domain
import Foundation
import Observation

/// State and actions for `TripSummaryView` (activity diagram 6).
@Observable
final class TripSummaryViewModel {
    enum FeedbackStep: Equatable {
        /// No warnings were given, so there's nothing to judge.
        case notAsked
        case asking
        case pickingWarning
        case thanks
        case saveFailed
    }

    let summary: TripSummary
    /// The hotspots the driver was warned about, in order, for "which warning wasn't useful?".
    let warnedHotspots: [RouteHotspot]
    private(set) var feedbackStep: FeedbackStep

    @ObservationIgnored private var log: TripLog
    @ObservationIgnored private let submitFeedback: SubmitTripFeedbackUseCase

    init(log: TripLog, plan: TripPlan, submitFeedback: SubmitTripFeedbackUseCase) {
        self.log = log
        self.submitFeedback = submitFeedback
        summary = TripSummary(log: log)
        // Hotspots from a re-routed detour aren't in the original plan; they just can't be picked here.
        let byID = Dictionary(plan.hotspots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        warnedHotspots = summary.warnedHotspotIDs.compactMap { byID[$0] }
        feedbackStep = summary.asksForFeedback ? .asking : .notAsked
    }

    func answerHelpful() async {
        await submit(.helpful)
    }

    /// With fewer than two warnings to show there's nothing to choose, so it's recorded straight away.
    func answerNotHelpful() async {
        if warnedHotspots.count >= 2 {
            feedbackStep = .pickingWarning
        } else if let id = warnedHotspots.first?.id ?? summary.warnedHotspotIDs.first {
            await submit(.notHelpful(hotspotID: id))
        }
    }

    func pick(_ hotspot: RouteHotspot) async {
        await submit(.notHelpful(hotspotID: hotspot.id))
    }

    /// Back from the picker without choosing.
    func cancelPicking() {
        feedbackStep = .asking
    }

    private func submit(_ feedback: WarningFeedback) async {
        do {
            log = try await submitFeedback(feedback, for: log)
            feedbackStep = .thanks
        } catch {
            feedbackStep = .saveFailed
        }
    }
}
