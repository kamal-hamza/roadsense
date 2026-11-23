import Application
import Domain
import Foundation
import SensorCore

/// Writes the open trip log as JSON lines (one per event) and saves finished logs as single JSON files.
public actor FileTripLogStore: TripLogStore {
    /// One line of the open log file.
    private enum Line: Codable {
        case header(TripLog)
        case entry(TripLogEntry)
    }

    private let directory: URL
    private var openLog: TripLog?

    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "RoadSense/TripLogs")
    }

    public init(directory: URL = FileTripLogStore.defaultDirectory) {
        self.directory = directory
    }

    private nonisolated var openLogURL: URL {
        directory.appending(path: "open.jsonl")
    }

    /// Where a finished log is saved.
    nonisolated func finishedLogURL(id: TripLog.ID) -> URL {
        directory.appending(path: "\(id.uuidString).json")
    }

    public func begin(_ log: TripLog) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Writable while the phone is locked, which is most of a drive.
        try encodeLine(.header(log)).write(
            to: openLogURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication],
        )
        openLog = log
    }

    public func append(_ entry: TripLogEntry) throws {
        guard openLog != nil else { return }
        let handle = try FileHandle(forWritingTo: openLogURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        // Appending one line per event means a crash loses at most the line being written.
        try handle.write(contentsOf: encodeLine(.entry(entry)))
        openLog?.append(entry)
    }

    public func finish(at time: Date, reason: TripEndReason, endCoordinate: Coordinate?) throws {
        guard var log = try openLog ?? readOpenLog() else { return }
        try log.finish(at: time, reason: reason, endCoordinate: endCoordinate)
        try JSONEncoder().encode(log)
            .write(
                to: finishedLogURL(id: log.id),
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication],
            )
        try FileManager.default.removeItem(at: openLogURL)
        openLog = nil
    }

    public func unfinishedLog() throws -> TripLog? {
        try openLog ?? readOpenLog()
    }

    /// Rebuilds the open log from its file, skipping a last line cut off by a crash.
    private func readOpenLog() throws -> TripLog? {
        guard FileManager.default.fileExists(atPath: openLogURL.path()) else { return nil }
        let decoder = JSONDecoder()
        var log: TripLog?
        for line in try Data(contentsOf: openLogURL).split(separator: UInt8(ascii: "\n")) {
            // A half-written line can only be the last one; everything before it is intact.
            guard let decoded = try? decoder.decode(Line.self, from: Data(line)) else { continue }
            switch decoded {
            case let .header(header): log = header
            case let .entry(entry): log?.append(entry)
            }
        }
        openLog = log
        return log
    }

    private func encodeLine(_ line: Line) throws -> Data {
        try JSONEncoder().encode(line) + Data("\n".utf8)
    }
}
