import OSLog

/// Logging for work the driver doesn't wait on (recovery, uploads); failures retry later, so they're logged, not shown.
enum BackgroundWork {
    static let logger = Logger(subsystem: "com.hkamal.RoadSense", category: "BackgroundWork")

    /// Runs `work`, logging (not throwing) a failure under `name`.
    static func run(_ name: StaticString, _ work: () async throws -> some Any) async {
        do {
            _ = try await work()
        } catch {
            logger.error("\(name, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
    }
}
