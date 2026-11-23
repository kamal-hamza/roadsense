import Domain
import SwiftUI

extension HotspotKind {
    var title: LocalizedStringKey {
        switch self {
        case .sharpCurve: "Sharp curve"
        case .shortMerge: "Short merge"
        case .suddenStop: "Sudden stops"
        }
    }

    var systemImage: String {
        switch self {
        case .sharpCurve: "arrow.turn.up.right"
        case .shortMerge: "arrow.triangle.merge"
        case .suddenStop: "exclamationmark.octagon.fill"
        }
    }
}
