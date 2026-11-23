import Application
import Domain
import Foundation
import Observation
import SensorCore
import SensorRecording

/// State and actions for `RecordingView`.
@Observable
final class RecordingViewModel {
    enum Phase: Equatable {
        case idle
        case starting
        case recording
        case saving
        case failed(message: String)
    }

    enum Signal: String, CaseIterable {
        case forward = "Forward"
        case sideways = "Sideways"
        case vertical = "Vertical"
    }

    struct ChartPoint: Identifiable, Equatable {
        let id: Int
        let time: Date
        let signal: Signal
        let value: Double
    }

    /// How much history the live chart shows.
    static let chartWindow: TimeInterval = 10

    private(set) var phase: Phase = .idle
    private(set) var snapshot: RecordingSnapshot?
    private(set) var chartPoints: [ChartPoint] = []
    private(set) var lastSavedTrip: Trip?
    var logsRawSensors = false

    @ObservationIgnored private let recordTrip: RecordTripUseCase
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var nextPointID = 0

    init(recordTrip: RecordTripUseCase) {
        self.recordTrip = recordTrip
    }

    var canStart: Bool {
        switch phase {
        case .idle, .failed: true
        case .starting, .recording, .saving: false
        }
    }

    func start() async {
        guard canStart else { return }
        phase = .starting
        do {
            let snapshots = try await recordTrip.start(logsRawSensors: logsRawSensors)
            snapshot = nil
            chartPoints = []
            phase = .recording
            // Feed live snapshots into the UI. weak self so the task doesn't keep this screen alive.
            updatesTask = Task { [weak self] in
                for await snapshot in snapshots {
                    self?.apply(snapshot)
                }
            }
        } catch {
            phase = .failed(message: error.localizedDescription)
        }
    }

    func stop() async {
        guard phase == .recording else { return }
        phase = .saving
        // Stop listening first so a last snapshot can't arrive after the trip is saved.
        updatesTask?.cancel()
        updatesTask = nil
        do {
            lastSavedTrip = try await recordTrip.stop()
            phase = .idle
        } catch {
            phase = .failed(message: error.localizedDescription)
        }
    }

    private func apply(_ snapshot: RecordingSnapshot) {
        self.snapshot = snapshot
        guard let motion = snapshot.motion else { return }
        // Forward acceleration only exists once the phone's alignment is learned.
        if let longitudinal = motion.longitudinal {
            appendPoint(.forward, longitudinal, at: motion.timestamp)
        }
        appendPoint(.sideways, motion.lateral, at: motion.timestamp)
        appendPoint(.vertical, motion.vertical, at: motion.timestamp)
        // Keep only the last 10 seconds so the chart scrolls and memory stays flat.
        let cutoff = motion.timestamp.addingTimeInterval(-Self.chartWindow)
        chartPoints.removeAll { $0.time < cutoff }
    }

    private func appendPoint(_ signal: Signal, _ value: Double, at time: Date) {
        chartPoints.append(ChartPoint(id: nextPointID, time: time, signal: signal, value: value))
        nextPointID += 1
    }
}
