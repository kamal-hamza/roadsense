#if os(iOS)
    import CoreLocation
    import CoreMotion
    import Foundation
    import SensorCore
    import SensorRecording

    /// Streams the phone's real sensors (device motion, GPS, activity), including in the background.
    public actor LiveSensorSource: SensorSource {
        private typealias Continuation = AsyncStream<SensorReading>.Continuation

        // Apple says to create only one motion manager per app.
        private let motionManager = CMMotionManager()
        private let activityManager = CMMotionActivityManager()
        private let sensorQueue: OperationQueue = {
            let queue = OperationQueue()
            queue.name = "com.hkamal.RoadSense.sensors"
            // Serial queue so motion and activity callbacks never run at the same time.
            queue.maxConcurrentOperationCount = 1
            return queue
        }()

        // Bumped per stream so a late cleanup from an old stream can't stop a new one.
        private var generation = 0
        private var continuation: Continuation?
        private var locationTask: Task<Void, Never>?
        private var backgroundSession: CLBackgroundActivitySession?
        private var serviceSession: CLServiceSession?

        public init() {}

        public func readings(configuration: SensorConfiguration) -> AsyncStream<SensorReading> {
            stopSensors()
            generation += 1
            let currentGeneration = generation
            let (stream, continuation) = AsyncStream.makeStream(
                of: SensorReading.self,
                // ~80 s of 50 Hz readings; if the consumer stalls longer, keep the newest.
                bufferingPolicy: .bufferingNewest(4096),
            )
            // When the consumer stops listening, turn the sensors off to save battery.
            continuation.onTermination = { _ in
                Task { await self.stopSensors(ifGeneration: currentGeneration) }
            }
            self.continuation = continuation

            startLocation(continuation)
            startMotion(configuration, continuation)
            startActivity(continuation)
            return stream
        }

        // MARK: - Starting

        private func startLocation(_ continuation: Continuation) {
            // These two sessions keep the app running (and receiving GPS) when the phone is locked.
            serviceSession = CLServiceSession(authorization: .whenInUse)
            backgroundSession = CLBackgroundActivitySession()
            locationTask = Task {
                do {
                    // Updates carry either a location or a status change (permission denied, etc.).
                    for try await update in CLLocationUpdate.liveUpdates(.automotiveNavigation) {
                        if let location = update.location {
                            continuation.yield(.location(LocationSample(location)))
                        } else if let status = LocationStatus(update) {
                            continuation.yield(.locationStatus(LocationStatusUpdate(timestamp: Date(), status: status)))
                        }
                    }
                } catch {
                    continuation.yield(.locationStatus(LocationStatusUpdate(timestamp: Date(), status: .unavailable)))
                }
            }
        }

        private func startMotion(_ configuration: SensorConfiguration, _ continuation: Continuation) {
            guard motionManager.isDeviceMotionAvailable else { return }
            motionManager.deviceMotionUpdateInterval = 1 / configuration.motionRateHz
            motionManager.startDeviceMotionUpdates(
                // Z is vertical, heading arbitrary; we avoid the compass since car metal skews it.
                using: .xArbitraryZVertical,
                to: sensorQueue,
                withHandler: Self.makeMotionHandler(continuation),
            )
        }

        private func startActivity(_ continuation: Continuation) {
            guard CMMotionActivityManager.isActivityAvailable() else { return }
            activityManager.startActivityUpdates(to: sensorQueue, withHandler: Self.makeActivityHandler(continuation))
        }

        // Built outside the actor as @Sendable: an actor-isolated closure called on `sensorQueue` traps.

        private static func makeMotionHandler(_ continuation: Continuation) -> CMDeviceMotionHandler {
            // Core Motion timestamps count from boot; this converts them to real dates.
            let bootDate = Date(timeIntervalSinceNow: -ProcessInfo.processInfo.systemUptime)
            return { @Sendable motion, _ in
                guard let motion else { return }
                continuation.yield(.motion(MotionSample(motion, bootDate: bootDate)))
            }
        }

        private static func makeActivityHandler(_ continuation: Continuation) -> CMMotionActivityHandler {
            { @Sendable activity in
                guard let activity else { return }
                continuation.yield(.activity(ActivitySample(activity)))
            }
        }

        // MARK: - Stopping

        private func stopSensors(ifGeneration expected: Int) {
            guard expected == generation else { return }
            stopSensors()
        }

        private func stopSensors() {
            motionManager.stopDeviceMotionUpdates()
            activityManager.stopActivityUpdates()
            locationTask?.cancel()
            locationTask = nil
            backgroundSession?.invalidate()
            backgroundSession = nil
            serviceSession?.invalidate()
            serviceSession = nil
            continuation?.finish()
            continuation = nil
        }
    }
#endif
