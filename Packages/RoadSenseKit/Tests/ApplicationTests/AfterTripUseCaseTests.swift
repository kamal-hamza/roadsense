import Application
import Domain
import Foundation
import SensorCore
import Testing

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let origin = Coordinate(latitude: 47.6, longitude: -122.3)
private let device = DeviceID(rawValue: UUID())

/// A finished 2 km drive north with a hotspot pass in the middle and a mute at the start.
private func finishedLog() throws -> TripLog {
    let north = Bearing(degrees: 0)
    var log = TripLog(startedAt: start, startCoordinate: origin)
    log.append(TripLogEntry(timestamp: start.addingTimeInterval(5), coordinate: nil, event: .muted))
    log.append(TripLogEntry(
        timestamp: start.addingTimeInterval(60),
        coordinate: origin.offset(by: 1000, toward: north),
        event: .hotspotPassed(hotspotID: UUID(), outcome: .suppressed, brakedHard: false),
    ))
    try log.finish(
        at: start.addingTimeInterval(150),
        reason: .arrived,
        endCoordinate: origin.offset(by: 2000, toward: north),
    )
    return log
}

struct SubmitTripFeedbackUseCaseTests {
    @Test func `adds the feedback to the log and saves it`() async throws {
        let store = MemoryLogStore(finished: [])
        let submit = SubmitTripFeedbackUseCase(tripLogStore: store, now: { start.addingTimeInterval(200) })
        let hotspotID = UUID()

        let updated = try await submit(.notHelpful(hotspotID: hotspotID), for: finishedLog())

        #expect(updated.entries.last?.event == .feedback(.notHelpful(hotspotID: hotspotID)))
        #expect(updated.entries.last?.coordinate == nil)
        #expect(await store.finished.first == updated)
    }
}

struct ManagePreferencesUseCaseTests {
    @Test func `saves and reads back the driver's choices`() async {
        let manage = ManagePreferencesUseCase(preferences: MemoryPreferences())

        let defaults = await manage()
        await manage.save(AppPreferences(warningsEnabled: false, dataSharingEnabled: false))
        let saved = await manage()

        #expect(defaults == AppPreferences(warningsEnabled: true, dataSharingEnabled: true))
        #expect(saved == AppPreferences(warningsEnabled: false, dataSharingEnabled: false))
    }
}

struct UploadPendingEventsUseCaseTests {
    private func makeUseCase(
        store: MemoryLogStore,
        queue: MemoryQueue = MemoryQueue(),
        uploader: ScriptedUploader,
        sharesData: Bool = true,
        now: Date = start.addingTimeInterval(300),
    ) -> UploadPendingEventsUseCase {
        UploadPendingEventsUseCase(
            tripLogStore: store,
            queue: queue,
            uploader: uploader,
            deviceIdentity: FixedDevice(),
            preferences: MemoryPreferences(AppPreferences(dataSharingEnabled: sharesData)),
            now: { now },
        )
    }

    @Test func `queues finished logs as trimmed events and sends them`() async throws {
        let store = try MemoryLogStore(finished: [finishedLog()])
        let queue = MemoryQueue()
        let uploader = ScriptedUploader([.accepted])

        let report = try await makeUseCase(store: store, queue: queue, uploader: uploader)()

        #expect(report == UploadReport(sent: 1))
        #expect(await store.finished.isEmpty)
        #expect(await queue.batches.isEmpty)
        let sent = try #require(await uploader.uploaded.first)
        #expect(sent.deviceID == device)
        guard case let .events(events) = sent.content else {
            Issue.record("Expected events, got \(sent.content)")
            return
        }
        // The mute and the mid-route pass survive trimming; nothing near the ends is in the log.
        #expect(events.count == 2)
        #expect(events.first?.event == .muted)
    }

    @Test func `with data sharing off only counts are sent`() async throws {
        let uploader = ScriptedUploader([.accepted])

        try await makeUseCase(store: MemoryLogStore(finished: [finishedLog()]), uploader: uploader, sharesData: false)()

        guard case let .counters(counters) = try #require(await uploader.uploaded.first).content else {
            Issue.record("Expected counters")
            return
        }
        #expect(counters.mutes == 1)
        #expect(counters.hotspotsPassed == 1)
    }

    @Test func `offline keeps everything queued for next time`() async throws {
        let queue = MemoryQueue()
        let uploader = ScriptedUploader([.failed])

        let report = try await makeUseCase(
            store: MemoryLogStore(finished: [finishedLog(), finishedLog()]),
            queue: queue,
            uploader: uploader,
        )()

        #expect(report == UploadReport(kept: 2))
        #expect(await queue.batches.count == 2)
        // It stops at the first failure instead of hammering a backend that's down.
        #expect(await uploader.uploaded.count == 1)
    }

    @Test func `an already-received batch is removed like an accepted one`() async throws {
        let queue = MemoryQueue()

        let report = try await makeUseCase(
            store: MemoryLogStore(finished: [finishedLog()]),
            queue: queue,
            uploader: ScriptedUploader([.alreadyReceived]),
        )()

        #expect(report.sent == 1)
        #expect(await queue.batches.isEmpty)
    }

    @Test func `an unknown device is registered once, then the batch is retried`() async throws {
        let uploader = ScriptedUploader([.deviceUnknown, .accepted])

        let report = try await makeUseCase(store: MemoryLogStore(finished: [finishedLog()]), uploader: uploader)()

        #expect(report.sent == 1)
        #expect(await uploader.registrations == [device])
    }

    @Test func `batches older than 30 days are dropped`() async throws {
        let old = UploadBatch(id: UUID(), deviceID: device, createdAt: start, content: .events([]))
        let queue = MemoryQueue(batches: [old])
        let uploader = ScriptedUploader([])

        let report = try await makeUseCase(
            store: MemoryLogStore(finished: []),
            queue: queue,
            uploader: uploader,
            now: start.addingTimeInterval(31 * 86400),
        )()

        #expect(report == UploadReport(dropped: 1))
        #expect(await uploader.uploaded.isEmpty)
    }

    @Test func `a log trimmed down to nothing isn't sent`() async throws {
        // Everything happens within 200 m of the start, so trimming leaves no events.
        var log = TripLog(startedAt: start, startCoordinate: origin)
        log.append(TripLogEntry(
            timestamp: start.addingTimeInterval(10),
            coordinate: origin,
            event: .hotspotPassed(hotspotID: UUID(), outcome: .missed, brakedHard: false),
        ))
        try log.finish(at: start.addingTimeInterval(20), reason: .arrived, endCoordinate: origin)
        let store = MemoryLogStore(finished: [log])
        let uploader = ScriptedUploader([])

        let report = try await makeUseCase(store: store, uploader: uploader)()

        #expect(report == UploadReport())
        #expect(await store.finished.isEmpty)
    }
}

private actor MemoryLogStore: TripLogStore {
    private(set) var finished: [TripLog]

    init(finished: [TripLog]) {
        self.finished = finished
    }

    func begin(_: TripLog) async throws {}
    func append(_: TripLogEntry) async throws {}
    func finish(at _: Date, reason _: TripEndReason, endCoordinate _: Coordinate?) async throws {}
    func unfinishedLog() async throws -> TripLog? {
        nil
    }

    func finishedLogs() async throws -> [TripLog] {
        finished
    }

    func saveFinished(_ log: TripLog) async throws {
        finished.removeAll { $0.id == log.id }
        finished.append(log)
    }

    func deleteFinished(id: TripLog.ID) async throws {
        finished.removeAll { $0.id == id }
    }
}

private actor MemoryQueue: UploadQueue {
    private(set) var batches: [UploadBatch]

    init(batches: [UploadBatch] = []) {
        self.batches = batches
    }

    func enqueue(_ batch: UploadBatch) async throws {
        batches.append(batch)
    }

    func pending() async throws -> [UploadBatch] {
        batches
    }

    func remove(id: UploadBatch.ID) async throws {
        batches.removeAll { $0.id == id }
    }
}

/// Answers uploads from a script; repeats the last answer once the script runs out.
private actor ScriptedUploader: EventUploader {
    private var script: [UploadResult]
    private(set) var uploaded: [UploadBatch] = []
    private(set) var registrations: [DeviceID] = []

    init(_ script: [UploadResult]) {
        self.script = script
    }

    func upload(_ batch: UploadBatch) async -> UploadResult {
        uploaded.append(batch)
        return script.count > 1 ? script.removeFirst() : (script.first ?? .accepted)
    }

    func registerDevice(_ deviceID: DeviceID) async throws {
        registrations.append(deviceID)
    }
}

private struct FixedDevice: DeviceIdentityStore {
    func deviceID() async throws -> DeviceID {
        device
    }
}

private actor MemoryPreferences: UserPreferences {
    private var stored: AppPreferences

    init(_ stored: AppPreferences = AppPreferences()) {
        self.stored = stored
    }

    func load() async -> AppPreferences {
        stored
    }

    func save(_ preferences: AppPreferences) async {
        stored = preferences
    }
}
