import Domain
import Foundation
import SensorCore
import Testing

struct TripTests {
    @Test func `trims name`() throws {
        let trip = try Trip(name: "  Commute ", startedAt: .now, distance: .init(value: 1, unit: .kilometers))
        #expect(trip.name == "Commute")
    }

    @Test(arguments: ["", "   "])
    func `rejects blank name`(name: String) {
        #expect(throws: TripError.emptyName) {
            try Trip(name: name, startedAt: .now, distance: .init(value: 1, unit: .kilometers))
        }
    }

    @Test func `rejects negative distance`() {
        #expect(throws: TripError.negativeDistance) {
            try Trip(name: "Commute", startedAt: .now, distance: .init(value: -1, unit: .meters))
        }
    }
}

struct TripLifecycleTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func `rejects ending before it started`() {
        #expect(throws: TripError.endsBeforeStart) {
            try Trip(
                name: "Commute",
                startedAt: start,
                endedAt: start.addingTimeInterval(-1),
                distance: .init(value: 1, unit: .kilometers),
            )
        }
    }

    @Test func `round-trips through JSON with its events`() throws {
        let event = DrivingEvent(
            kind: .hardBrake,
            timestamp: start.addingTimeInterval(30.123),
            duration: 1.2,
            peakAcceleration: 0.45,
            speed: 15,
            course: 90,
            coordinate: Coordinate(latitude: 47.6, longitude: -122.3),
            confidence: 0.9,
        )
        let trip = try Trip(
            name: "Commute",
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            distance: .init(value: 5.5, unit: .kilometers),
            events: [event],
        )

        let decoded = try JSONDecoder().decode(Trip.self, from: JSONEncoder().encode(trip))

        #expect(decoded == trip)
    }

    @Test func `decoding enforces invariants`() {
        let json = Data(#"{"id":"\#(UUID().uuidString)","name":" ","startedAt":0,"distanceMeters":1}"#.utf8)

        #expect(throws: TripError.emptyName) {
            try JSONDecoder().decode(Trip.self, from: json)
        }
    }
}
