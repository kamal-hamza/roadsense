import Application
import Domain
import Foundation

/// Keeps queued upload batches as one JSON file each, so removing one can't corrupt the others.
public actor FileUploadQueue: UploadQueue {
    private let directory: URL

    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "RoadSense/UploadQueue")
    }

    public init(directory: URL = FileUploadQueue.defaultDirectory) {
        self.directory = directory
    }

    public func enqueue(_ batch: UploadBatch) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(batch)
            .write(to: url(for: batch.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    public func pending() throws -> [UploadBatch] {
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return [] }
        let decoder = JSONDecoder()
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try decoder.decode(UploadBatch.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    public func remove(id: UploadBatch.ID) throws {
        let fileURL = url(for: id)
        // Removing twice (e.g. a retried upload) is fine.
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private func url(for id: UploadBatch.ID) -> URL {
        directory.appending(path: "\(id.uuidString).json")
    }
}
