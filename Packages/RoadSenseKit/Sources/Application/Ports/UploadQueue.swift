import Domain
import Foundation

/// Batches waiting to be uploaded, kept on the phone until the backend accepts them. Implemented in Infrastructure.
public protocol UploadQueue: Sendable {
    func enqueue(_ batch: UploadBatch) async throws

    /// Every queued batch, oldest first.
    func pending() async throws -> [UploadBatch]

    func remove(id: UploadBatch.ID) async throws
}
