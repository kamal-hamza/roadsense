import Domain
import Foundation
import SensorCore

/// Writes the trip log to disk as the drive goes, so it survives the app being killed. Implemented in Infrastructure.
public protocol TripLogStore: Sendable {
    /// Starts a new log. Only one log is open at a time.
    func begin(_ log: TripLog) async throws

    /// Adds an entry to the open log.
    func append(_ entry: TripLogEntry) async throws

    /// Closes the open log.
    func finish(at time: Date, reason: TripEndReason, endCoordinate: Coordinate?) async throws

    /// A log that was started but never finished (the app was closed mid-drive), if any.
    func unfinishedLog() async throws -> TripLog?

    /// Finished logs waiting to be turned into uploads, oldest first.
    func finishedLogs() async throws -> [TripLog]

    /// Replaces a finished log, e.g. after the driver's feedback is added.
    func saveFinished(_ log: TripLog) async throws

    /// Removes a finished log once its events are queued for upload.
    func deleteFinished(id: TripLog.ID) async throws
}
