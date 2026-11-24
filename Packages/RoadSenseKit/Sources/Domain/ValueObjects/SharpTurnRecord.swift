import Foundation

/// A sharp turn near a hotspot on the route, sent as evidence that the hotspot is a curve.
public struct SharpTurnRecord: Hashable, Sendable, Codable {
    /// Peak sideways acceleration, in g.
    public let peakLateralAcceleration: Double
    /// A few GPS fixes around the turn, so the backend can check the car stayed on one road.
    public let trace: [TracePoint]

    public init(peakLateralAcceleration: Double, trace: [TracePoint]) {
        self.peakLateralAcceleration = peakLateralAcceleration
        self.trace = trace
    }

    /// The same record with a different trace (used when trimming fixes near home or work).
    public func withTrace(_ newTrace: [TracePoint]) -> SharpTurnRecord {
        SharpTurnRecord(peakLateralAcceleration: peakLateralAcceleration, trace: newTrace)
    }
}
