import Application
import Domain
import SwiftUI

/// The big, glanceable top banner: the active warning with a countdown, or what's next.
struct WarningBanner: View {
    let update: DriveUpdate

    var body: some View {
        if let warning = update.activeWarning, let first = warning.hotspots.first {
            HStack(spacing: 16) {
                Image(systemName: first.hotspot.kind.systemImage)
                    .font(.system(.largeTitle, weight: .bold))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    if warning.hotspots.count > 1 {
                        Text("^[\(warning.hotspots.count) hazards](inflect: true) ahead")
                            .font(.title.bold())
                    } else {
                        Text(first.hotspot.kind.title)
                            .font(.title.bold())
                    }
                    if let distance = update.distanceToWarning {
                        Text(DriveFormat.distance(max(0, distance)))
                            .font(.title2.monospacedDigit())
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .foregroundStyle(.black)
            .background(.orange, in: .rect(cornerRadius: 20))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        } else {
            StatusCard(update: update)
        }
    }
}

/// What the top of the screen says when there's no warning right now.
private struct StatusCard: View {
    let update: DriveUpdate

    var body: some View {
        Group {
            if update.gpsStatus == .lost {
                Label("GPS signal lost", systemImage: "location.slash")
            } else if !update.hasHazardData {
                Label("No hazard data for this route", systemImage: "exclamationmark.icloud")
            } else if update.isMuted {
                Label("Warnings muted", systemImage: "speaker.slash.fill")
            } else if let next = update.nextHotspot {
                Label {
                    HStack(spacing: 8) {
                        Text(next.hotspot.kind.title)
                        Text(DriveFormat.distance(max(0, next.distanceAlongRoute - update.distanceAlongRoute)))
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: next.hotspot.kind.systemImage)
                }
            } else {
                Label("No more hazards on this route", systemImage: "checkmark.circle")
            }
        }
        .font(.title3.weight(.semibold))
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
    }
}

/// Distances and speeds in the driver's units.
enum DriveFormat {
    static func distance(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))
    }

    static func speed(_ metersPerSecond: Double) -> String {
        Measurement(value: max(0, metersPerSecond), unit: UnitSpeed.metersPerSecond)
            .formatted(.measurement(
                width: .abbreviated,
                usage: .general,
                numberFormatStyle: .number.precision(.fractionLength(0)),
            ))
    }
}
