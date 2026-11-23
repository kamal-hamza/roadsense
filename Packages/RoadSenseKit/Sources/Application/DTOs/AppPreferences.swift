/// The driver's choices in Settings.
public struct AppPreferences: Hashable, Sendable, Codable {
    /// Off means every drive starts muted (still logged, for success metric 2).
    public var warningsEnabled: Bool
    /// Off means only anonymous counts are uploaded: no places and no hotspots.
    public var dataSharingEnabled: Bool

    public init(warningsEnabled: Bool = true, dataSharingEnabled: Bool = true) {
        self.warningsEnabled = warningsEnabled
        self.dataSharingEnabled = dataSharingEnabled
    }
}
