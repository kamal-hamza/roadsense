import Foundation
import SensorCore

public enum SensorRecorderError: Error, Equatable, Sendable, LocalizedError {
    case alreadyRecording
    case notRecording

    public var errorDescription: String? {
        switch self {
        case .alreadyRecording: "A recording is already in progress."
        case .notRecording: "Nothing is being recorded."
        }
    }
}

/// What a finished recording produced.
public struct RecordingSummary: Hashable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date
    public let distanceMeters: Double
    public let events: [DrivingEvent]

    public init(id: UUID, startedAt: Date, endedAt: Date, distanceMeters: Double, events: [DrivingEvent]) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distanceMeters = distanceMeters
        self.events = events
    }
}

/// Runs a recording: feeds readings through detection, tracks distance, and publishes snapshots.
public actor SensorRecorder {
    public struct Options: Hashable, Sendable {
        public var logsRawSensors: Bool
        public var sensors: SensorConfiguration

        public init(logsRawSensors: Bool = false, sensors: SensorConfiguration = SensorConfiguration()) {
            self.logsRawSensors = logsRawSensors
            self.sensors = sensors
        }
    }

    private struct Session {
        let id: UUID
        let startedAt: Date
        var isLogging: Bool
        var pipeline = DetectionPipeline()
        var odometer = TripOdometer()
        var events: [DrivingEvent] = []
        var latestSpeed: Double?
        var latestActivity: ActivitySample?
        var locationStatus: LocationStatus?
        var logBuffer: [SensorReading] = []
        var lastSnapshotAt: Date?
        let continuation: AsyncStream<RecordingSnapshot>.Continuation
        var task: Task<Void, Never>?
    }

    /// Readings are written to the log in batches of this size.
    private static let logBatchSize = 500
    /// Live snapshots are published at most this often (seconds of sensor time), plus on every event.
    private static let snapshotInterval: TimeInterval = 0.1

    private let sensorSource: any SensorSource
    private let sensorLogStore: any SensorLogStore
    private let now: @Sendable () -> Date
    private var session: Session?

    public init(
        sensorSource: any SensorSource,
        sensorLogStore: any SensorLogStore,
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.sensorSource = sensorSource
        self.sensorLogStore = sensorLogStore
        self.now = now
    }

    public var isRecording: Bool {
        session != nil
    }

    /// Starts recording and returns live snapshots until the sensors stop or `stop()` is called.
    public func start(options: Options = Options()) async throws(SensorRecorderError)
        -> AsyncStream<RecordingSnapshot>
    {
        guard session == nil else { throw .alreadyRecording }
        let (snapshots, continuation) = AsyncStream.makeStream(
            of: RecordingSnapshot.self,
            // The UI only needs the latest state; drop stale snapshots if it falls behind.
            bufferingPolicy: .bufferingNewest(1),
        )
        let id = UUID()
        session = Session(id: id, startedAt: now(), isLogging: options.logsRawSensors, continuation: continuation)

        if options.logsRawSensors {
            do {
                try await sensorLogStore.beginLog(recordingID: id)
                // Recording without a raw log is still useful, so carry on if the file can't open.
            } catch {
                session?.isLogging = false
            }
        }

        let readings = await sensorSource.readings(configuration: options.sensors)
        // Runs on this actor, so readings are processed one at a time, in order.
        session?.task = Task {
            for await reading in readings {
                await self.handle(reading)
            }
            // Reached only if the source ran out (e.g. a replay ended), not on stop().
            self.sensorsFinished()
        }
        return snapshots
    }

    /// Stops recording and returns what it produced.
    public func stop() async throws(SensorRecorderError) -> RecordingSummary {
        guard let current = session else { throw .notRecording }
        if let task = current.task {
            task.cancel()
            // Wait for the loop to exit so no reading is mid-way through when we save.
            await task.value
        }
        // Re-check after the await: a second stop() may have finished first.
        guard let finished = session else { throw .notRecording }
        session = nil
        finished.continuation.finish()

        if finished.isLogging {
            if !finished.logBuffer.isEmpty {
                try? await sensorLogStore.append(finished.logBuffer)
            }
            try? await sensorLogStore.finishLog()
        }

        return RecordingSummary(
            id: finished.id,
            startedAt: finished.startedAt,
            // Guard against the clock moving backwards (e.g. a time zone or NTP change).
            endedAt: max(now(), finished.startedAt),
            distanceMeters: finished.odometer.meters,
            events: finished.events,
        )
    }

    // MARK: - Processing

    private func handle(_ reading: SensorReading) async {
        // Work on a copy and write it back before any await, so stop() never sees half an update.
        guard var current = session else { return }
        let newEvents = current.pipeline.process(reading)
        current.events.append(contentsOf: newEvents)
        record(reading, in: &current)

        var batchToLog: [SensorReading]?
        if current.isLogging {
            current.logBuffer.append(reading)
            if current.logBuffer.count >= Self.logBatchSize {
                batchToLog = current.logBuffer
                current.logBuffer.removeAll(keepingCapacity: true)
            }
        }

        // ~10 snapshots a second is plenty for the UI; always send one when an event fires.
        let isSnapshotDue = current.lastSnapshotAt.map {
            abs(reading.timestamp.timeIntervalSince($0)) >= Self.snapshotInterval
        } ?? true
        if !newEvents.isEmpty || isSnapshotDue {
            current.lastSnapshotAt = reading.timestamp
            current.continuation.yield(Self.snapshot(of: current))
        }
        session = current

        // Disk writes happen after the state is saved, in batches, to keep the 50 Hz loop light.
        if let batchToLog {
            try? await sensorLogStore.append(batchToLog)
        }
    }

    private func record(_ reading: SensorReading, in session: inout Session) {
        switch reading {
        case let .location(location):
            session.odometer.add(location)
            session.latestSpeed = location.speed
        case let .activity(activity):
            session.latestActivity = activity
        case let .locationStatus(update):
            session.locationStatus = update.status
        case .motion:
            break
        }
    }

    private func sensorsFinished() {
        guard let session, !Task.isCancelled else { return }
        session.continuation.yield(Self.snapshot(of: session))
        session.continuation.finish()
    }

    private static func snapshot(of session: Session) -> RecordingSnapshot {
        RecordingSnapshot(
            recordingID: session.id,
            startedAt: session.startedAt,
            speed: session.latestSpeed,
            distanceMeters: session.odometer.meters,
            motion: session.pipeline.latestMotion,
            isFrameReady: session.pipeline.isFrameReady,
            frameConfidence: session.pipeline.frameConfidence,
            activity: session.latestActivity,
            locationStatus: session.locationStatus,
            events: session.events,
            isLoggingRawSensors: session.isLogging,
        )
    }
}
