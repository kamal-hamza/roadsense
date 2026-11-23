#if os(iOS)
    import CoreLocation
    import Foundation
    import SensorCore
    import SensorRecording

    /// Location permission and current position from Core Location.
    public struct LiveLocationServices: LocationServices {
        /// How long to wait for a fix before giving up.
        public var fixTimeout: Duration

        public init(fixTimeout: Duration = .seconds(10)) {
            self.fixTimeout = fixTimeout
        }

        public func authorization() async -> LocationAuthorization {
            // CLLocationManager wants to live on a thread with a run loop, so read it on the main actor.
            await MainActor.run { LocationAuthorization(CLLocationManager().authorizationStatus) }
        }

        public func requestAuthorization() async -> LocationAuthorization {
            let current = await authorization()
            guard current == .notDetermined else { return current }
            let request = await AuthorizationRequest()
            return await LocationAuthorization(request.run())
        }

        public func currentLocation() async throws -> LocationSample {
            let timeout = fixTimeout
            return try await withThrowingTaskGroup(of: LocationSample.self) { group in
                group.addTask { try await Self.firstFix() }
                // Whichever finishes first wins: a fix, or the timeout.
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw LocationServicesError.unavailable
                }
                defer { group.cancelAll() }
                guard let fix = try await group.next() else { throw LocationServicesError.unavailable }
                return fix
            }
        }

        private static func firstFix() async throws -> LocationSample {
            var isDenied = false
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    if let location = update.location {
                        return LocationSample(location)
                    }
                    if update.authorizationDenied || update.authorizationDeniedGlobally || update
                        .authorizationRestricted
                    {
                        isDenied = true
                        break
                    }
                }
            } catch {
                throw LocationServicesError.unavailable
            }
            throw isDenied ? LocationServicesError.notAuthorized : LocationServicesError.unavailable
        }
    }

    /// Shows the When In Use prompt and waits for the answer through the delegate.
    @MainActor
    private final class AuthorizationRequest: NSObject, CLLocationManagerDelegate {
        private let manager = CLLocationManager()
        private var continuation: CheckedContinuation<CLAuthorizationStatus, Never>?

        func run() async -> CLAuthorizationStatus {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                manager.delegate = self
                manager.requestWhenInUseAuthorization()
            }
        }

        nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            let status = manager.authorizationStatus
            Task { @MainActor in self.finish(with: status) }
        }

        private func finish(with status: CLAuthorizationStatus) {
            // The delegate also fires right after it's set, before the user has answered.
            guard status != .notDetermined, let continuation else { return }
            self.continuation = nil
            continuation.resume(returning: status)
        }
    }

    extension LocationAuthorization {
        init(_ status: CLAuthorizationStatus) {
            switch status {
            case .notDetermined: self = .notDetermined
            case .restricted: self = .restricted
            case .denied: self = .denied
            case .authorizedAlways, .authorizedWhenInUse: self = .authorized
            // Treat anything new as "no access" until we know what it means.
            @unknown default: self = .denied
            }
        }
    }
#endif
