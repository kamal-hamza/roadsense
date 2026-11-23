import Foundation

/// Deterministic random numbers (SplitMix64) so synthetic drives are reproducible.
struct SeededRandom: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func nextUnit() -> Double {
        // &+ and &* wrap on overflow instead of crashing, which this algorithm relies on.
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value >> 11) / Double(1 << 53)
    }

    /// Normally distributed value (Box–Muller).
    mutating func gaussian(standardDeviation: Double) -> Double {
        // Avoid log(0).
        let first = max(nextUnit(), 1e-12)
        let second = nextUnit()
        return standardDeviation * (-2 * log(first)).squareRoot() * cos(2 * .pi * second)
    }

    mutating func gaussianVector(standardDeviation: Double) -> SIMD3<Double> {
        SIMD3(
            gaussian(standardDeviation: standardDeviation),
            gaussian(standardDeviation: standardDeviation),
            gaussian(standardDeviation: standardDeviation),
        )
    }
}
