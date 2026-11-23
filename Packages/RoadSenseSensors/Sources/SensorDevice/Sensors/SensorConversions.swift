#if os(iOS)
    import CoreLocation
    import CoreMotion
    import Foundation
    import SensorCore

    // Convert Apple sensor objects to SensorCore values here, so nothing else needs Core Motion/Location.

    extension MotionSample {
        /// - Parameter bootDate: Wall-clock time of device boot. Core Motion timestamps count from boot.
        init(_ motion: CMDeviceMotion, bootDate: Date) {
            self.init(
                timestamp: bootDate.addingTimeInterval(motion.timestamp),
                gravity: SIMD3(motion.gravity.x, motion.gravity.y, motion.gravity.z),
                userAcceleration: SIMD3(
                    motion.userAcceleration.x,
                    motion.userAcceleration.y,
                    motion.userAcceleration.z,
                ),
                rotationRate: SIMD3(motion.rotationRate.x, motion.rotationRate.y, motion.rotationRate.z),
            )
        }
    }

    extension LocationSample {
        /// Negative accuracy values mean Core Location considers the value invalid.
        init(_ location: CLLocation) {
            // Core Location marks invalid values with negatives; turn those into nil.
            let hasSpeed = location.speedAccuracy >= 0 && location.speed >= 0
            let hasCourse = location.courseAccuracy >= 0 && location.course >= 0
            self.init(
                timestamp: location.timestamp,
                coordinate: Coordinate(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                ),
                horizontalAccuracy: location.horizontalAccuracy,
                speed: hasSpeed ? location.speed : nil,
                speedAccuracy: hasSpeed ? location.speedAccuracy : nil,
                course: hasCourse ? location.course : nil,
                courseAccuracy: hasCourse ? location.courseAccuracy : nil,
            )
        }
    }

    extension ActivitySample {
        init(_ activity: CMMotionActivity) {
            var kinds: Set<Kind> = []
            if activity.stationary {
                kinds.insert(.stationary)
            }
            if activity.walking {
                kinds.insert(.walking)
            }
            if activity.running {
                kinds.insert(.running)
            }
            if activity.cycling {
                kinds.insert(.cycling)
            }
            if activity.automotive {
                kinds.insert(.automotive)
            }
            if activity.unknown {
                kinds.insert(.unknown)
            }
            let confidence: Confidence = switch activity.confidence {
            case .high: .high
            case .medium: .medium
            default: .low
            }
            self.init(timestamp: activity.startDate, kinds: kinds, confidence: confidence)
        }
    }

    extension LocationStatus {
        /// The most important condition reported by a location update, if any.
        init?(_ update: CLLocationUpdate) {
            if update.authorizationDenied || update.authorizationDeniedGlobally {
                self = .denied
            } else if update.authorizationRestricted {
                self = .restricted
            } else if update.accuracyLimited {
                self = .accuracyLimited
            } else if update.insufficientlyInUse {
                self = .needsForeground
            } else if update.locationUnavailable {
                self = .unavailable
            } else if update.authorizationRequestInProgress {
                self = .requestingAuthorization
            } else if update.stationary {
                self = .stationary
            } else {
                return nil
            }
        }
    }
#endif
