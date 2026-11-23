import Domain

/// Speaks, vibrates, or notifies to warn the driver. Implemented in Infrastructure.
public protocol DriveAlerting: Sendable {
    /// Gets ready before the drive starts (e.g. asks to send notifications).
    func prepare() async

    /// Warns about `warning`: speech (vibration only on a call), plus a notification when the app isn't on screen.
    func announce(_ warning: DriveWarning) async
}
