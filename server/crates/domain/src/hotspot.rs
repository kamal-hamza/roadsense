//! Hotspots: places where many different drivers brake hard, going one way.

use chrono::{DateTime, Utc};
use uuid::Uuid;

use crate::geo::{Bearing, Coordinate};

/// What makes a hotspot dangerous, decided from the road shape around it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum HotspotKind {
    SharpCurve,
    ShortMerge,
    SuddenStop,
}

/// Candidates collect votes but are never shown to drivers; active ones are.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum HotspotStatus {
    Candidate,
    Active,
}

/// A place and direction of travel where drivers brake hard.
#[derive(Debug, Clone, PartialEq)]
pub struct Hotspot {
    pub id: Uuid,
    pub kind: HotspotKind,
    pub status: HotspotStatus,
    pub location: Coordinate,
    /// The direction of travel it applies to; the same spot can be harmless the other way.
    pub bearing: Bearing,
    pub created_at: DateTime<Utc>,
    /// Too many drivers said its warning wasn't helpful; someone should check it (road fixed? bad data?).
    pub flagged_for_review: bool,
}

impl Hotspot {
    /// A new candidate hotspot at a hard brake.
    pub fn candidate(location: Coordinate, bearing: Bearing, kind: HotspotKind, now: DateTime<Utc>) -> Self {
        Self {
            id: Uuid::new_v4(),
            kind,
            status: HotspotStatus::Candidate,
            location,
            bearing,
            created_at: now,
            flagged_for_review: false,
        }
    }
}

/// A hotspot with how many different drivers flagged it in the consensus window.
#[derive(Debug, Clone, PartialEq)]
pub struct CountedHotspot {
    pub hotspot: Hotspot,
    pub driver_count: u32,
}

/// A hotspot placed on a driver's route.
#[derive(Debug, Clone, PartialEq)]
pub struct RouteHotspot {
    pub hotspot: Hotspot,
    pub driver_count: u32,
    /// Meters from the route's start to the hotspot.
    pub distance_along_route: f64,
}
