import Application
import Domain
import Foundation

/// Keeps recently fetched hotspot areas in a JSON file in Caches, for offline warnings.
public actor FileHotspotCache: HotspotCache {
    private let fileURL: URL
    private let maximumAreas: Int
    private var loaded: [CachedHotspotArea]?

    public static var defaultFileURL: URL {
        URL.cachesDirectory.appending(path: "RoadSense/hotspot-areas.json")
    }

    /// - Parameter maximumAreas: How many areas to keep; the oldest are dropped first.
    public init(fileURL: URL = FileHotspotCache.defaultFileURL, maximumAreas: Int = 20) {
        self.fileURL = fileURL
        self.maximumAreas = maximumAreas
    }

    public func save(_ area: CachedHotspotArea) throws {
        // Newest first, trimmed so the file can't grow without limit.
        let areas = try Array(([area] + load()).prefix(maximumAreas))
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        // Atomic so a crash mid-write can't corrupt the file; readable while the phone is locked.
        try JSONEncoder().encode(areas)
            .write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        loaded = areas
    }

    public func areas() throws -> [CachedHotspotArea] {
        try load()
    }

    private func load() throws -> [CachedHotspotArea] {
        // Read the file once, then serve from memory.
        if let loaded {
            return loaded
        }
        guard FileManager.default.fileExists(atPath: fileURL.path()) else {
            loaded = []
            return []
        }
        let areas = try JSONDecoder().decode([CachedHotspotArea].self, from: Data(contentsOf: fileURL))
        loaded = areas
        return areas
    }
}
