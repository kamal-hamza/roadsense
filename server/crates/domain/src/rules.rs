//! The tunable rules from the use case. Starting values; see docs/MVP_USE_CASE_1.md §1.

use chrono::{DateTime, Duration, Utc};

use crate::geo::{Bearing, Coordinate};
use crate::hotspot::Hotspot;

/// How many different drivers, over how long, make a hotspot worth warning about.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Consensus {
    pub minimum_drivers: u32,
    pub window: Duration,
}

impl Default for Consensus {
    fn default() -> Self {
        // Five drivers keeps one person's odd braking from triggering warnings for everyone.
        Self {
            minimum_drivers: 5,
            window: Duration::days(365),
        }
    }
}

impl Consensus {
    /// Votes older than this don't count, so a road that was fixed stops producing warnings.
    pub fn window_start(&self, now: DateTime<Utc>) -> DateTime<Utc> {
        now - self.window
    }

    pub fn is_met(&self, distinct_drivers: u32) -> bool {
        distinct_drivers >= self.minimum_drivers
    }
}

/// When a hard brake (or a route) counts as being at a hotspot.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct HotspotMatch {
    /// Meters from the hotspot.
    pub radius: f64,
    /// Degrees the direction of travel may differ from the hotspot's.
    pub heading_tolerance: f64,
}

impl Default for HotspotMatch {
    fn default() -> Self {
        Self {
            radius: 30.0,
            heading_tolerance: 45.0,
        }
    }
}

impl HotspotMatch {
    pub fn matches(&self, hotspot: &Hotspot, location: &Coordinate, bearing: Bearing) -> bool {
        hotspot.location.distance_to(location) <= self.radius
            && hotspot.bearing.is_aligned(bearing, self.heading_tolerance)
    }
}

/// When enough drivers say a hotspot's warning wasn't helpful that someone should look at it.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct FeedbackReview {
    pub minimum_replies: u32,
    pub not_helpful_share: f64,
}

impl Default for FeedbackReview {
    fn default() -> Self {
        Self {
            minimum_replies: 10,
            not_helpful_share: 0.3,
        }
    }
}

impl FeedbackReview {
    pub fn needs_review(&self, helpful: u32, not_helpful: u32) -> bool {
        let total = helpful + not_helpful;
        // Too few replies says nothing; wait for at least ten.
        total >= self.minimum_replies && f64::from(not_helpful) / f64::from(total) >= self.not_helpful_share
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::geo::test_support::point;
    use crate::hotspot::HotspotKind;

    #[test]
    fn consensus_needs_five_drivers_within_a_year() {
        let consensus = Consensus::default();
        assert!(!consensus.is_met(4));
        assert!(consensus.is_met(5));
        let now = DateTime::<Utc>::from_timestamp(1_800_000_000, 0).expect("valid time");
        assert_eq!(now - consensus.window_start(now), Duration::days(365));
    }

    #[test]
    fn matching_needs_30_m_and_the_same_direction() {
        let now = Utc::now();
        let hotspot = Hotspot::candidate(point(0.0, 0.0), Bearing::new(0.0), HotspotKind::SuddenStop, now);
        let rule = HotspotMatch::default();
        assert!(rule.matches(&hotspot, &point(29.0, 0.0), Bearing::new(40.0)));
        assert!(!rule.matches(&hotspot, &point(31.0, 0.0), Bearing::new(0.0)));
        assert!(!rule.matches(&hotspot, &point(10.0, 0.0), Bearing::new(180.0)));
    }

    #[test]
    fn review_needs_ten_replies_and_30_percent_not_helpful() {
        let review = FeedbackReview::default();
        assert!(!review.needs_review(2, 7), "only 9 replies");
        assert!(review.needs_review(7, 3));
        assert!(!review.needs_review(8, 3));
    }
}
