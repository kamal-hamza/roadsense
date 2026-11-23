import Application
import Domain
import Foundation
import OSLog

/// Accepts every upload without sending anything, until the server exists (M6). Never ship it.
public struct DemoEventUploader: EventUploader {
    private static let logger = Logger(subsystem: "com.hkamal.RoadSense", category: "Upload")
    /// Simulates the backend being unreachable, to try the retry queue.
    public var isOffline: Bool

    public init(isOffline: Bool = false) {
        self.isOffline = isOffline
    }

    public func upload(_ batch: UploadBatch) async -> UploadResult {
        guard !isOffline else { return .failed }
        switch batch.content {
        case let .events(events):
            Self.logger.info("Demo upload accepted \(events.count) events")
        case .counters:
            Self.logger.info("Demo upload accepted anonymous counters")
        }
        return .accepted
    }

    public func registerDevice(_: DeviceID) async throws {}
}
