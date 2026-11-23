import Application
import Domain
import Foundation

/// Stores trips as a JSON file in Application Support.
public actor FileTripRepository: TripRepository {
    private let fileURL: URL
    private var cache: [Trip.ID: Trip]?

    public static var defaultFileURL: URL {
        URL.applicationSupportDirectory.appending(path: "RoadSense/trips.json")
    }

    public init(fileURL: URL = FileTripRepository.defaultFileURL) {
        self.fileURL = fileURL
    }

    public func allTrips() throws -> [Trip] {
        try Array(loadTrips().values)
    }

    public func save(_ trip: Trip) throws {
        var trips = try loadTrips()
        trips[trip.id] = trip
        try persist(trips)
        cache = trips
    }

    private func loadTrips() throws -> [Trip.ID: Trip] {
        // Read the file once, then serve from memory.
        if let cache {
            return cache
        }
        guard FileManager.default.fileExists(atPath: fileURL.path()) else {
            cache = [:]
            return [:]
        }
        let decoder = JSONDecoder()
        let trips = try decoder.decode([Trip].self, from: Data(contentsOf: fileURL))
        // Tolerate duplicate IDs in an old file instead of crashing.
        let tripsByID = Dictionary(trips.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        cache = tripsByID
        return tripsByID
    }

    private func persist(_ trips: [Trip.ID: Trip]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(trips.values.sorted { $0.startedAt < $1.startedAt })
        // Atomic so a crash mid-write can't corrupt the file; writable while the phone is locked.
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
