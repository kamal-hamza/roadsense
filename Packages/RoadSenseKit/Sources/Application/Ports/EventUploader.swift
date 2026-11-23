import Domain

/// Sends privacy-trimmed event batches to the backend. Implemented in Infrastructure.
public protocol EventUploader: Sendable {
    func upload(_ batch: UploadBatch) async -> UploadResult

    /// Tells the backend about this device's anonymous id.
    func registerDevice(_ deviceID: DeviceID) async throws
}
