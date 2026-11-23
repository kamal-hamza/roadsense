import Foundation
import SensorCore
import SensorRecording

/// Writes raw sensor logs as JSON Lines files in `Documents/SensorLogs/` (visible in Files).
public actor FileSensorLogStore: SensorLogStore {
    private let directory: URL
    private let encoder = SensorLogCoding.makeEncoder()
    private var handle: FileHandle?

    public static var defaultDirectory: URL {
        URL.documentsDirectory.appending(path: "SensorLogs", directoryHint: .isDirectory)
    }

    public init(directory: URL = FileSensorLogStore.defaultDirectory) {
        self.directory = directory
    }

    public func beginLog(recordingID: UUID) throws {
        try finishLog()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL(recordingID: recordingID)
        FileManager.default.createFile(
            atPath: url.path(percentEncoded: false),
            contents: nil,
            // Writable while the phone is locked during a drive ("complete" protection isn't).
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        )
        handle = try FileHandle(forWritingTo: url)
    }

    public func append(_ readings: [SensorReading]) throws {
        guard let handle else { return }
        var data = Data()
        for reading in readings {
            try data.append(encoder.encode(reading))
            // Newline: one JSON reading per line (JSON Lines).
            data.append(0x0A)
        }
        try handle.write(contentsOf: data)
    }

    public func finishLog() throws {
        try handle?.close()
        handle = nil
    }

    public func logURL(recordingID: UUID) -> URL? {
        let url = fileURL(recordingID: recordingID)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    private func fileURL(recordingID: UUID) -> URL {
        directory.appending(path: "recording-\(recordingID.uuidString).jsonl")
    }

    /// Reads every reading from a JSON Lines sensor log.
    public static func readLog(at url: URL) throws -> [SensorReading] {
        let decoder = SensorLogCoding.makeDecoder()
        let data = try Data(contentsOf: url)
        return try data.split(separator: 0x0A).map { try decoder.decode(SensorReading.self, from: Data($0)) }
    }
}

/// Shared JSON settings for sensor logs. Dates are Unix seconds, easy to read from Python.
enum SensorLogCoding {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
