import Application
import Domain
import Foundation
@testable import Presentation
import SensorCore
import Testing

struct TripSummaryViewModelTests {
    private let hotspots: [RouteHotspot]
    private let plan: TripPlan

    init() throws {
        let start = Coordinate(latitude: 47.6, longitude: -122.3)
        let end = start.offset(by: 2000, toward: Bearing(degrees: 0))
        hotspots = [500.0, 1200].map { distance in
            RouteHotspot(
                hotspot: Hotspot(
                    id: UUID(),
                    kind: .sharpCurve,
                    coordinate: start,
                    bearing: Bearing(degrees: 0),
                    driverCount: 5,
                ),
                distanceAlongRoute: distance,
            )
        }
        plan = try TripPlan(
            destination: Place(name: "End", coordinate: end),
            route: Route(name: "Test Rd", points: [start, end], expectedTravelTime: 150),
            hotspots: hotspots,
            freshness: .live,
        )
    }

    private func log(warnedAbout warned: [RouteHotspot]) -> TripLog {
        var log = TripLog(startedAt: .now, startCoordinate: nil)
        for hotspot in warned {
            log.append(TripLogEntry(
                timestamp: .now,
                coordinate: nil,
                event: .warningShown(hotspotIDs: [hotspot.id], speed: 14),
            ))
        }
        try? log.finish(at: .now, reason: .arrived, endCoordinate: nil)
        return log
    }

    private func makeViewModel(warnedAbout warned: [RouteHotspot], store: SavingLogStore) -> TripSummaryViewModel {
        TripSummaryViewModel(
            log: log(warnedAbout: warned),
            plan: plan,
            submitFeedback: SubmitTripFeedbackUseCase(tripLogStore: store),
        )
    }

    @Test func `no warnings means no question`() {
        let viewModel = makeViewModel(warnedAbout: [], store: SavingLogStore())

        #expect(viewModel.feedbackStep == .notAsked)
    }

    @Test func `helpful is saved`() async {
        let store = SavingLogStore()
        let viewModel = makeViewModel(warnedAbout: hotspots, store: store)

        await viewModel.answerHelpful()

        #expect(viewModel.feedbackStep == .thanks)
        #expect(await store.saved.last?.entries.last?.event == .feedback(.helpful))
    }

    @Test func `not helpful asks which warning when there were several`() async {
        let store = SavingLogStore()
        let viewModel = makeViewModel(warnedAbout: hotspots, store: store)

        await viewModel.answerNotHelpful()
        let step = viewModel.feedbackStep
        await viewModel.pick(hotspots[1])

        #expect(step == .pickingWarning)
        #expect(viewModel.warnedHotspots == hotspots)
        #expect(await store.saved.last?.entries.last?.event == .feedback(.notHelpful(hotspotID: hotspots[1].id)))
    }

    @Test func `not helpful with one warning is recorded straight away`() async {
        let store = SavingLogStore()
        let viewModel = makeViewModel(warnedAbout: [hotspots[0]], store: store)

        await viewModel.answerNotHelpful()

        #expect(viewModel.feedbackStep == .thanks)
        #expect(await store.saved.last?.entries.last?.event == .feedback(.notHelpful(hotspotID: hotspots[0].id)))
    }

    @Test func `a failed save says so`() async {
        let viewModel = makeViewModel(warnedAbout: hotspots, store: SavingLogStore(fails: true))

        await viewModel.answerHelpful()

        #expect(viewModel.feedbackStep == .saveFailed)
    }
}

private actor SavingLogStore: TripLogStore {
    private(set) var saved: [TripLog] = []
    private let fails: Bool

    init(fails: Bool = false) {
        self.fails = fails
    }

    func begin(_: TripLog) async throws {}
    func append(_: TripLogEntry) async throws {}
    func finish(at _: Date, reason _: TripEndReason, endCoordinate _: Coordinate?) async throws {}
    func unfinishedLog() async throws -> TripLog? {
        nil
    }

    func finishedLogs() async throws -> [TripLog] {
        saved
    }

    func saveFinished(_ log: TripLog) async throws {
        if fails {
            throw CocoaError(.fileWriteNoPermission)
        }
        saved.append(log)
    }

    func deleteFinished(id _: TripLog.ID) async throws {}
}
