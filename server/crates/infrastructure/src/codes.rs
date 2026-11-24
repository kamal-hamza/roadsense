//! Text codes for enums stored in the database. Keep in sync with the CHECK constraints in migrations/.

use roadsense_domain::events::{EventKind, PassOutcome};
use roadsense_domain::hotspot::{HotspotKind, HotspotSource, HotspotStatus};

pub fn kind_code(kind: HotspotKind) -> &'static str {
    match kind {
        HotspotKind::SharpCurve => "sharp_curve",
        HotspotKind::ShortMerge => "short_merge",
        HotspotKind::SuddenStop => "sudden_stop",
    }
}

pub fn kind_from_code(code: &str) -> HotspotKind {
    match code {
        "sharp_curve" => HotspotKind::SharpCurve,
        "short_merge" => HotspotKind::ShortMerge,
        // The CHECK constraint allows nothing else; sudden stops is the safe default.
        _ => HotspotKind::SuddenStop,
    }
}

pub fn status_code(status: HotspotStatus) -> &'static str {
    match status {
        HotspotStatus::Candidate => "candidate",
        HotspotStatus::Active => "active",
    }
}

pub fn status_from_code(code: &str) -> HotspotStatus {
    if code == "active" {
        HotspotStatus::Active
    } else {
        HotspotStatus::Candidate
    }
}

/// The `source` column, plus the `reported_crashes` column that goes with it.
pub fn source_code(source: HotspotSource) -> (&'static str, Option<i32>) {
    match source {
        HotspotSource::Drivers => ("drivers", None),
        HotspotSource::CityCollisions { crashes } => {
            ("city_collisions", Some(i32::try_from(crashes).unwrap_or(i32::MAX)))
        }
    }
}

pub fn source_from_code(code: &str, reported_crashes: Option<i32>) -> HotspotSource {
    match (code, reported_crashes) {
        ("city_collisions", Some(crashes)) => HotspotSource::CityCollisions {
            crashes: u32::try_from(crashes).unwrap_or(0),
        },
        // Anything else came from drivers: the default, and the one that still needs votes.
        _ => HotspotSource::Drivers,
    }
}

pub fn event_code(kind: &EventKind) -> &'static str {
    match kind {
        EventKind::HardBrake(_) => "hard_brake",
        EventKind::HotspotPassed { .. } => "hotspot_passed",
        EventKind::WarningShown { .. } => "warning_shown",
        EventKind::WarningSuppressed { .. } => "warning_suppressed",
        EventKind::Muted => "muted",
        EventKind::Unmuted => "unmuted",
        EventKind::Feedback { .. } => "feedback",
    }
}

pub fn outcome_code(outcome: PassOutcome) -> &'static str {
    match outcome {
        PassOutcome::Warned { .. } => "warned",
        PassOutcome::Suppressed => "suppressed",
        PassOutcome::Missed => "missed",
    }
}
