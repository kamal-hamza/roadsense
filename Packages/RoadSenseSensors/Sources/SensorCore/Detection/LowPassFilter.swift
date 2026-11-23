import Foundation

/// First-order low-pass filter that adapts to irregular sample timing.
struct LowPassFilter: Sendable {
    let cutoffHz: Double
    private(set) var value: Double?
    private var lastTimestamp: Date?

    init(cutoffHz: Double) {
        self.cutoffHz = cutoffHz
    }

    mutating func update(_ input: Double, at timestamp: Date) -> Double {
        guard let value, let lastTimestamp else {
            value = input
            lastTimestamp = timestamp
            return input
        }
        let elapsed = max(0, timestamp.timeIntervalSince(lastTimestamp))
        // Classic RC filter, computed from the real gap so irregular sample timing still works.
        let timeConstant = 1 / (2 * .pi * cutoffHz)
        let smoothing = elapsed / (timeConstant + elapsed)
        let filtered = value + smoothing * (input - value)
        self.value = filtered
        self.lastTimestamp = timestamp
        return filtered
    }

    mutating func reset() {
        value = nil
        lastTimestamp = nil
    }
}
