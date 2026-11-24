import Foundation

/// What the driver sees after a drive (activity diagram 6).
public struct TripSummary: Hashable, Sendable {
    public let hotspotsPassed: Int
    public let warningsGiven: Int
    public let hardBrakes: Int
    /// Hard brakes linked to a hotspot.
    public let hardBrakesNearHotspots: Int
    public let sharpTurns: Int
    /// Hotspots the driver was warned about, in order, for the "which warning wasn't useful?" picker.
    public let warnedHotspotIDs: [UUID]

    /// Only ask for feedback if there was at least one warning to judge.
    public var asksForFeedback: Bool {
        warningsGiven > 0
    }

    /// Builds the summary from a trip log.
    /// - Complexity: O(*n*) in the number of log entries.
    public init(log: TripLog) {
        var passed = 0
        var warnings = 0
        var brakes = 0
        var brakesNearHotspots = 0
        var turns = 0
        var warnedIDs: [UUID] = []
        for entry in log.entries {
            switch entry.event {
            case .hotspotPassed:
                passed += 1
            case let .warningShown(hotspotIDs, _):
                warnings += 1
                warnedIDs += hotspotIDs.filter { !warnedIDs.contains($0) }
            case let .hardBrake(record):
                brakes += 1
                if record.nearestHotspotID != nil {
                    brakesNearHotspots += 1
                }
            case .sharpTurn:
                turns += 1
            case .warningSuppressed, .muted, .unmuted, .feedback:
                break
            }
        }
        hotspotsPassed = passed
        warningsGiven = warnings
        hardBrakes = brakes
        hardBrakesNearHotspots = brakesNearHotspots
        sharpTurns = turns
        warnedHotspotIDs = warnedIDs
    }
}
