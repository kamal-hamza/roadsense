import Application
import Domain
import Foundation

/// Uploads privacy-trimmed event batches to the RoadSense server.
public struct HTTPEventUploader: EventUploader {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func upload(_ batch: UploadBatch) async -> UploadResult {
        do {
            let (_, status) = try await client.post(
                "v1/events",
                body: UploadRequestDTO(batch),
                deviceID: batch.deviceID,
            )
            return switch status {
            case 202: .accepted
            case 200: .alreadyReceived
            case 401: .deviceUnknown
            case 429: .rateLimited
            default: .failed
            }
        } catch {
            // Offline or timed out: the batch stays queued.
            return .failed
        }
    }

    public func registerDevice(_ deviceID: DeviceID) async throws {
        try await client.registerDevice(deviceID)
    }
}
