import Domain
import Foundation

/// Turns finished trip logs into privacy-trimmed batches and sends what's queued (activity diagram 6).
/// Trips themselves never leave the phone; see docs/MVP_USE_CASE_1.md §5.2.
public struct UploadPendingEventsUseCase: Sendable {
    private let tripLogStore: any TripLogStore
    private let queue: any UploadQueue
    private let uploader: any EventUploader
    private let deviceIdentity: any DeviceIdentityStore
    private let preferences: any UserPreferences
    private let trimmer: PrivacyTrimmer
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID

    public init(
        tripLogStore: any TripLogStore,
        queue: any UploadQueue,
        uploader: any EventUploader,
        deviceIdentity: any DeviceIdentityStore,
        preferences: any UserPreferences,
        trimmer: PrivacyTrimmer = PrivacyTrimmer(),
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init,
    ) {
        self.tripLogStore = tripLogStore
        self.queue = queue
        self.uploader = uploader
        self.deviceIdentity = deviceIdentity
        self.preferences = preferences
        self.trimmer = trimmer
        self.now = now
        self.makeID = makeID
    }

    /// Queues every finished log, then uploads the queue until it's empty or the backend can't take more.
    /// - Throws: Only local storage errors; network trouble just leaves batches queued.
    @discardableResult
    public func callAsFunction() async throws -> UploadReport {
        let deviceID = try await deviceIdentity.deviceID()
        try await queueFinishedLogs(deviceID: deviceID)
        return try await sendQueue(deviceID: deviceID)
    }

    private func queueFinishedLogs(deviceID: DeviceID) async throws {
        let sharesData = await preferences.load().dataSharingEnabled
        for log in try await tripLogStore.finishedLogs() {
            let content: UploadContent = sharesData
                ? .events(trimmer.events(from: log, makeID: makeID))
                : .counters(trimmer.counters(from: log, makeID: makeID))
            // A short trip can trim down to nothing; there's no point sending an empty batch.
            if case let .events(events) = content, events.isEmpty {
                try await tripLogStore.deleteFinished(id: log.id)
                continue
            }
            // Queue before deleting: a crash in between could resend a trip, but never loses one.
            try await queue.enqueue(UploadBatch(id: makeID(), deviceID: deviceID, createdAt: now(), content: content))
            try await tripLogStore.deleteFinished(id: log.id)
        }
    }

    private func sendQueue(deviceID: DeviceID) async throws -> UploadReport {
        var report = UploadReport()
        var hasReregistered = false
        let pending = try await queue.pending()
        for (index, batch) in pending.enumerated() {
            if batch.isExpired(at: now()) {
                try await queue.remove(id: batch.id)
                report.dropped += 1
                continue
            }
            var result = await uploader.upload(batch)
            // An unknown device gets one re-registration per pass, then one more try.
            if result == .deviceUnknown, !hasReregistered {
                hasReregistered = true
                if await (try? uploader.registerDevice(deviceID)) != nil {
                    result = await uploader.upload(batch)
                }
            }
            switch result {
            case .accepted, .alreadyReceived:
                try await queue.remove(id: batch.id)
                report.sent += 1
            case .deviceUnknown:
                report.kept += 1
            case .rateLimited, .failed:
                // The backend can't take more right now; leave the rest for the next launch or trip.
                report.kept += pending.count - index
                return report
            }
        }
        return report
    }
}
