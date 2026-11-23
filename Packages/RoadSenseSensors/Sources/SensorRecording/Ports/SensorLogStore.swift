import Foundation
import SensorCore

/// Stores raw sensor readings per recording. Only one log is open at a time.
public protocol SensorLogStore: Sendable {
    /// Opens a new log for `recordingID`, closing any open log.
    func beginLog(recordingID: UUID) async throws

    /// Appends readings to the open log. Does nothing if no log is open.
    func append(_ readings: [SensorReading]) async throws

    /// Closes the open log.
    func finishLog() async throws

    /// The file holding the log for `recordingID`, if one exists.
    func logURL(recordingID: UUID) async -> URL?
}
