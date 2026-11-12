import Domain
import Foundation
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
