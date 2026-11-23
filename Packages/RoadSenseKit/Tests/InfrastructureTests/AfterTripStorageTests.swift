import Application
import Domain
import Foundation
@testable import Infrastructure
import Testing

struct FileUploadQueueTests {
    private func batch(createdAt seconds: TimeInterval) -> UploadBatch {
        UploadBatch(
            id: UUID(),
            deviceID: DeviceID(rawValue: UUID()),
            createdAt: Date(timeIntervalSinceReferenceDate: seconds),
            content: .events([UploadEvent(id: UUID(), hour: .now, event: .muted)]),
        )
    }

    @Test func `keeps batches oldest first across instances, and removes them`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "File UploadQueue Tests-\(UUID().uuidString)")
        let older = batch(createdAt: 1)
        let newer = batch(createdAt: 2)
        try await FileUploadQueue(directory: directory).enqueue(newer)
        try await FileUploadQueue(directory: directory).enqueue(older)

        let pending = try await FileUploadQueue(directory: directory).pending()
        try await FileUploadQueue(directory: directory).remove(id: older.id)
        try await FileUploadQueue(directory: directory).remove(id: older.id)
        let afterRemove = try await FileUploadQueue(directory: directory).pending()

        #expect(pending == [older, newer])
        #expect(afterRemove == [newer])
    }

    @Test func `an empty queue has nothing pending`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "File UploadQueue Tests-\(UUID().uuidString)")

        #expect(try await FileUploadQueue(directory: directory).pending().isEmpty)
    }
}

struct UserDefaultsPreferencesTests {
    @Test func `defaults to warnings and sharing on, then remembers changes`() async throws {
        let suite = "UserDefaultsPreferencesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = UserDefaultsPreferences(suiteName: suite)

        let initial = await preferences.load()
        await preferences.save(AppPreferences(warningsEnabled: false, dataSharingEnabled: true))
        let saved = await UserDefaultsPreferences(suiteName: suite).load()

        #expect(initial == AppPreferences())
        #expect(saved == AppPreferences(warningsEnabled: false, dataSharingEnabled: true))
    }
}

struct DemoEventUploaderTests {
    @Test func `accepts uploads, or fails when offline`() async {
        let batch = UploadBatch(id: UUID(), deviceID: DeviceID(rawValue: UUID()), createdAt: .now, content: .events([]))

        #expect(await DemoEventUploader().upload(batch) == .accepted)
        #expect(await DemoEventUploader(isOffline: true).upload(batch) == .failed)
    }
}
