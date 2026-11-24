import Domain
import Foundation
import OSLog

/// Talks JSON to the RoadSense server (API v1). Errors are left to the adapters, which map them to app errors.
public struct APIClient: Sendable {
    private static let logger = Logger(subsystem: "com.hkamal.RoadSense", category: "Network")
    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// The server's dates are ISO-8601, so both directions use that instead of Foundation's default.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// POSTs `body` as JSON to `path`, with the device id header when given. Returns the body and status code.
    /// - Throws: `URLError` for network failures.
    func post(_ path: String, body: some Encodable, deviceID: DeviceID? = nil) async throws -> (Data, Int) {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        // A driver waiting at Start Drive shouldn't wait long; the hotspot lookup retries on its own.
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let deviceID {
            request.setValue(deviceID.rawValue.uuidString, forHTTPHeaderField: "X-Device-ID")
        }
        request.httpBody = try Self.makeEncoder().encode(body)
        let started = ContinuousClock.now
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            Self.logger
                .info("POST \(path, privacy: .public) -> \(status) in \(started.duration(to: .now), privacy: .public)")
            return (data, status)
        } catch {
            Self.logger.error("POST \(path, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    /// Tells the server about this device. Registering again is fine.
    /// - Throws: `URLError`, or `HotspotServiceError.unavailable` if the server refused.
    func registerDevice(_ deviceID: DeviceID) async throws {
        let (_, status) = try await post("v1/devices", body: RegisterDeviceRequestDTO(deviceId: deviceID.rawValue))
        guard (200 ..< 300).contains(status) else { throw URLError(.badServerResponse) }
    }
}

/// Body of `POST /v1/devices`.
struct RegisterDeviceRequestDTO: Encodable {
    let deviceId: UUID
}
