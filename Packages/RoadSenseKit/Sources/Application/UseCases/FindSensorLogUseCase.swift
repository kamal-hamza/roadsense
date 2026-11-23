import Foundation
import SensorRecording

/// Returns the raw sensor log recorded with a trip, if any.
public struct FindSensorLogUseCase: Sendable {
    private let store: any SensorLogStore

    public init(store: any SensorLogStore) {
        self.store = store
    }

    /// Trips share their ID with the recording that produced them.
    public func callAsFunction(tripID: UUID) async -> URL? {
        await store.logURL(recordingID: tripID)
    }
}
