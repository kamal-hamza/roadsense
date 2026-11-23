import SensorCore
import SwiftUI

extension DrivingEventKind {
    var title: LocalizedStringKey {
        switch self {
        case .hardBrake: "Hard brake"
        case .hardAcceleration: "Hard acceleration"
        case .sharpTurn: "Sharp turn"
        case .swerve: "Swerve"
        case .bump: "Bump"
        }
    }

    var systemImage: String {
        switch self {
        case .hardBrake: "hand.raised.fill"
        case .hardAcceleration: "hare.fill"
        case .sharpTurn: "arrow.turn.up.right"
        case .swerve: "arrow.left.arrow.right"
        case .bump: "waveform.path"
        }
    }
}
