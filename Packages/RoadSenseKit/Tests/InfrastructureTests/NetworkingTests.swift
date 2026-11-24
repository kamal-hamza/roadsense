import Application
import Domain
import Foundation
@testable import Infrastructure
import SensorCore
import Synchronization
import Testing

/// Answers requests from a script per host, so tests running in parallel don't see each other's replies.
final class StubURLProtocol: URLProtocol {
    struct Reply {
        let status: Int
        let body: Data
    }

    /// Requests run on URLSession's own threads, so the script and the request log are behind a Mutex.
    private static let state = Mutex<(replies: [String: [Reply]], requests: [String: [URLRequest]])>(([:], [:]))

    static func script(host: String, _ replies: [Reply]) {
        state.withLock { $0.replies[host] = replies }
    }

    static func requests(host: String) -> [URLRequest] {
        state.withLock { $0.requests[host] ?? [] }
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let host = request.url?.host() ?? ""
        // URLSession moves the body into a stream; read it back so tests can inspect what was sent.
        var recorded = request
        if recorded.httpBody == nil, let stream = request.httpBodyStream {
            recorded.httpBody = Data(reading: stream)
        }
        let reply = Self.state.withLock { state -> Reply? in
            state.requests[host, default: []].append(recorded)
            guard var replies = state.replies[host], !replies.isEmpty else { return nil }
            let next = replies.removeFirst()
            state.replies[host] = replies
            return next
        }
        guard let reply, let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil, headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension Data {
    init(reading stream: InputStream) {
        self.init()
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            append(buffer, count: count)
        }
    }
}

private struct FixedDevice: DeviceIdentityStore {
    let id = DeviceID(rawValue: UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID())

    func deviceID() async throws -> DeviceID {
        id
    }
}

/// A client whose requests go to the stub, on a host unique to this test.
private func makeClient() -> (APIClient, String) {
    let host = "test-\(UUID().uuidString.lowercased()).example"
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let client = APIClient(baseURL: URL(string: "https://\(host)")!, session: URLSession(configuration: configuration))
    return (client, host)
}

private func reply(_ status: Int, _ json: String = "") -> StubURLProtocol.Reply {
    StubURLProtocol.Reply(status: status, body: Data(json.utf8))
}

private func makeRoute() throws -> Route {
    let start = Coordinate(latitude: 47.6062, longitude: -122.3321)
    return try Route(
        name: "Test",
        points: [start, start.offset(by: 2000, toward: Bearing(degrees: 0))],
        expectedTravelTime: 120,
    )
}

struct HTTPHotspotServiceTests {
    @Test func `decodes the server's hotspots`() async throws {
        let (client, host) = makeClient()
        let id = UUID()
        StubURLProtocol.script(host: host, [reply(200, """
        {"hotspots":[{"id":"\(id)","kind":"shortMerge","latitude":47.61,"longitude":-122.33,"bearing":2.5,\
        "driverCount":7,"distanceAlongRoute":812.5},\
        {"id":"\(UUID())","kind":"suddenStop","latitude":47.62,"longitude":-122.33,"bearing":0,\
        "driverCount":0,"distanceAlongRoute":1500,"reportedCrashes":12}]}
        """)])

        let hotspots = try await HTTPHotspotService(client: client, deviceIdentity: FixedDevice())
            .hotspots(along: makeRoute())

        #expect(hotspots.count == 2)
        #expect(hotspots[0].id == id)
        #expect(hotspots[0].hotspot.kind == .shortMerge)
        #expect(hotspots[0].hotspot.driverCount == 7)
        #expect(hotspots[0].distanceAlongRoute == 812.5)
        // Driver-reported hotspots carry no crash count; ones from the city's records do.
        #expect(hotspots[0].hotspot.reportedCrashes == nil)
        #expect(hotspots[1].hotspot.reportedCrashes == 12)
        let request = try #require(StubURLProtocol.requests(host: host).first)
        #expect(request.url?.path() == "/v1/routes/hotspots")
        #expect(request.value(forHTTPHeaderField: "X-Device-ID") == FixedDevice().id.rawValue.uuidString)
    }

    @Test func `an unregistered device registers once and asks again`() async throws {
        let (client, host) = makeClient()
        StubURLProtocol.script(host: host, [reply(401), reply(201), reply(200, #"{"hotspots":[]}"#)])

        let hotspots = try await HTTPHotspotService(client: client, deviceIdentity: FixedDevice())
            .hotspots(along: makeRoute())

        #expect(hotspots.isEmpty)
        #expect(StubURLProtocol.requests(host: host).map { $0.url?.path() } == [
            "/v1/routes/hotspots",
            "/v1/devices",
            "/v1/routes/hotspots",
        ])
    }

    @Test(arguments: [(400, HotspotServiceError.rejected), (503, .unavailable), (500, .unavailable)])
    func `maps refusals and server errors`(status: Int, expected: HotspotServiceError) async {
        let (client, host) = makeClient()
        StubURLProtocol.script(host: host, [reply(status)])

        await #expect(throws: expected) {
            try await HTTPHotspotService(client: client, deviceIdentity: FixedDevice()).hotspots(along: makeRoute())
        }
    }

    @Test func `no connection is unavailable`() async {
        let (client, _) = makeClient()

        await #expect(throws: HotspotServiceError.unavailable) {
            try await HTTPHotspotService(client: client, deviceIdentity: FixedDevice()).hotspots(along: makeRoute())
        }
    }
}

struct HTTPEventUploaderTests {
    private func batch(_ content: UploadContent) -> UploadBatch {
        UploadBatch(
            id: UUID(),
            deviceID: FixedDevice().id,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            content: content,
        )
    }

    @Test(arguments: [
        (202, UploadResult.accepted), (200, .alreadyReceived), (401, .deviceUnknown), (429, .rateLimited), (
            503,
            .failed,
        ),
    ])
    func `maps the server's answer`(status: Int, expected: UploadResult) async {
        let (client, host) = makeClient()
        StubURLProtocol.script(host: host, [reply(status)])

        let result = await HTTPEventUploader(client: client).upload(batch(.events([])))

        #expect(result == expected)
    }

    @Test func `no connection fails so the batch stays queued`() async {
        let (client, _) = makeClient()

        #expect(await HTTPEventUploader(client: client).upload(batch(.events([]))) == .failed)
    }

    @Test func `sends events in the server's wire format, with no trip id`() async throws {
        let (client, host) = makeClient()
        StubURLProtocol.script(host: host, [reply(202)])
        let hour = Date(timeIntervalSince1970: 1_800_000_000)
        let hotspot = UUID()
        let brake = HardBrakeRecord(
            course: 90,
            speedBefore: 18,
            speedAfter: 6,
            peakDeceleration: 0.5,
            nearestHotspotID: hotspot,
            wasWarned: true,
            secondsSinceWarning: 6,
            trace: [TracePoint(coordinate: Coordinate(latitude: 47.6, longitude: -122.3), course: 90)],
        )
        let events = [
            UploadEvent(id: UUID(), hour: hour, event: .hardBrake(brake)),
            UploadEvent(
                id: UUID(),
                hour: hour,
                event: .hotspotPassed(hotspotID: hotspot, outcome: .warned(secondsOfWarning: 9), brakedHard: true),
            ),
            UploadEvent(id: UUID(), hour: hour, event: .feedback(.notHelpful(hotspotID: hotspot))),
            UploadEvent(id: UUID(), hour: hour, event: .muted),
        ]

        _ = await HTTPEventUploader(client: client).upload(batch(.events(events)))

        let body = try #require(StubURLProtocol.requests(host: host).first?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let sent = try #require(json["events"] as? [[String: Any]])
        #expect(json["counters"] == nil)
        #expect(json["tripId"] == nil)
        #expect(sent.map { $0["type"] as? String } == ["hardBrake", "hotspotPassed", "feedback", "muted"])
        #expect(sent[0]["hour"] as? String == "2027-01-15T08:00:00Z")
        #expect((sent[0]["trace"] as? [[String: Any]])?.first?["latitude"] as? Double == 47.6)
        #expect(sent[1]["outcome"] as? String == "warned")
        #expect(sent[1]["secondsOfWarning"] as? Double == 9)
        #expect(sent[2]["helpful"] as? Bool == false)
        #expect(sent[2]["hotspotId"] as? String == hotspot.uuidString)
    }

    @Test func `sends only counters when data sharing is off`() async throws {
        let (client, host) = makeClient()
        StubURLProtocol.script(host: host, [reply(202)])
        let counters = UsageCounters(
            id: UUID(),
            hour: .now,
            warningsShown: 2,
            warningsSuppressed: 0,
            mutes: 1,
            hotspotsPassed: 2,
        )

        _ = await HTTPEventUploader(client: client).upload(batch(.counters(counters)))

        let body = try #require(StubURLProtocol.requests(host: host).first?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["events"] == nil)
        #expect((json["counters"] as? [String: Any])?["mutes"] as? Int == 1)
    }
}
