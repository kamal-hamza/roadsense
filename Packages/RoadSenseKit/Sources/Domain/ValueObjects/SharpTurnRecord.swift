import Foundation

/// A sharp turn during a drive. Ones near a hotspot on the route are sent as evidence that the hotspot is a curve.
public struct SharpTurnRecord: Hashable, Sendable, Codable {
    /// Peak sideways acceleration, in g.
    public let peakLateralAcceleration: Double
    /// The hotspot on the route the turn was near, if any. Only those turns are uploaded.
    public let nearestHotspotID: UUID?
    /// A few GPS fixes around the turn, so the backend can check the car stayed on one road.
    public let trace: [TracePoint]

    public init(peakLateralAcceleration: Double, nearestHotspotID: UUID?, trace: [TracePoint]) {
        self.peakLateralAcceleration = peakLateralAcceleration
        self.nearestHotspotID = nearestHotspotID
        self.trace = trace
    }

    /// The same record with a different trace (used when trimming fixes near home or work).
    public func withTrace(_ newTrace: [TracePoint]) -> SharpTurnRecord {
        SharpTurnRecord(
            peakLateralAcceleration: peakLateralAcceleration,
            nearestHotspotID: nearestHotspotID,
            trace: newTrace,
        )
    }
}
