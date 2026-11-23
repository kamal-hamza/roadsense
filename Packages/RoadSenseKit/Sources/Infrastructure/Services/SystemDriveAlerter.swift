import Application
import AVFoundation
import Domain
import Foundation
import OSLog
import UserNotifications

#if os(iOS)
    import AudioToolbox
    import CallKit
    import UIKit
#endif

/// Warns with speech (vibration only during a phone call) and a notification when the app isn't on screen.
public struct SystemDriveAlerter: DriveAlerting {
    private let output: AlertOutput

    @MainActor
    public init() {
        output = AlertOutput()
    }

    public func prepare() async {
        await output.requestNotificationPermission()
    }

    public func announce(_ warning: DriveWarning) async {
        await output.announce(warning)
    }

    /// What to say for `warning`, e.g. "Sharp curve in 200 meters" or "2 hazards ahead in 150 meters".
    static func phrase(for warning: DriveWarning, locale: Locale = .current) -> String {
        // Round to 50 m so it sounds natural; nobody needs "187 meters" while driving.
        let rounded = max(50, (warning.distance / 50).rounded() * 50)
        let distance = Measurement(value: rounded, unit: UnitLength.meters)
            .formatted(.measurement(width: .wide, usage: .road).locale(locale))
        guard warning.hotspots.count == 1, let kind = warning.hotspots.first?.hotspot.kind else {
            return String(localized: "\(warning.hotspots.count) hazards ahead in \(distance)")
        }
        return switch kind {
        case .sharpCurve: String(localized: "Sharp curve in \(distance)")
        case .shortMerge: String(localized: "Short merge in \(distance)")
        case .suddenStop: String(localized: "Sudden stops ahead in \(distance)")
        }
    }
}

/// The main-actor side: the speech synthesizer, audio session, and notifications.
@MainActor
private final class AlertOutput: NSObject, AVSpeechSynthesizerDelegate {
    private nonisolated static let logger = Logger(subsystem: "com.hkamal.RoadSense", category: "Alerts")
    /// The system doesn't retain the synthesizer, so keep a strong reference for the app's lifetime.
    private let synthesizer = AVSpeechSynthesizer()
    #if os(iOS)
        private let callObserver = CXCallObserver()
    #endif

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func requestNotificationPermission() async {
        do {
            // Asked when the first drive starts, right before warnings can be needed; "no" is fine.
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
        } catch {
            Self.logger.error("Notification permission request failed: \(error.localizedDescription)")
        }
    }

    func announce(_ warning: DriveWarning) {
        let phrase = SystemDriveAlerter.phrase(for: warning)
        if isOnCall {
            vibrate()
        } else {
            speak(phrase)
        }
        if !isAppOnScreen {
            postNotification(phrase)
        }
    }

    private var isOnCall: Bool {
        #if os(iOS)
            callObserver.calls.contains { !$0.hasEnded }
        #else
            false
        #endif
    }

    private var isAppOnScreen: Bool {
        #if os(iOS)
            UIApplication.shared.applicationState == .active
        #else
            true
        #endif
    }

    private func speak(_ phrase: String) {
        #if os(iOS)
            do {
                // Apple's recommended setup for navigation prompts: duck music, pause spoken audio like podcasts.
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(
                    .playback,
                    mode: .voicePrompt,
                    options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers],
                )
                try session.setActive(true)
            } catch {
                Self.logger.error("Couldn't start the audio session: \(error.localizedDescription)")
            }
        #endif
        synthesizer.speak(AVSpeechUtterance(string: phrase))
    }

    private func vibrate() {
        #if os(iOS)
            // Works in the background too, unlike UIKit's feedback generators.
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        #endif
    }

    private func postNotification(_ phrase: String) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Hazard ahead")
        content.body = phrase
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Self.logger.error("Couldn't post the warning notification: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
        Task { @MainActor in self.releaseAudio() }
    }

    nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, didCancel _: AVSpeechUtterance) {
        Task { @MainActor in self.releaseAudio() }
    }

    /// Gives the audio back right after speaking, so music comes back to full volume (Apple: duck only briefly).
    private func releaseAudio() {
        #if os(iOS)
            guard !synthesizer.isSpeaking else { return }
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                Self.logger.error("Couldn't release the audio session: \(error.localizedDescription)")
            }
        #endif
    }
}
