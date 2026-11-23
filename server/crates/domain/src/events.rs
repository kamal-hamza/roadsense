//! What the app uploads: individual, privacy-trimmed events with no trip id or route.

use chrono::{DateTime, Duration, Utc};
use thiserror::Error;
use uuid::Uuid;

use crate::geo::{Bearing, Coordinate};

/// One GPS fix near a hard brake (no timestamp), so the brake can be placed on a road and direction.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct TracePoint {
    pub location: Coordinate,
    /// Direction of travel in degrees, if the GPS had one.
    pub course: Option<f64>,
}

/// A hard brake as the app logged it.
#[derive(Debug, Clone, PartialEq)]
pub struct HardBrake {
    pub course: Option<f64>,
    /// Speeds in m/s.
    pub speed_before: Option<f64>,
    pub speed_after: Option<f64>,
    /// Peak deceleration in g.
    pub peak_deceleration: f64,
    pub nearest_hotspot_id: Option<Uuid>,
    pub was_warned: bool,
    pub seconds_since_warning: Option<f64>,
    pub trace: Vec<TracePoint>,
}

impl HardBrake {
    /// Where the brake happened and which way the car was going: the middle of the trace and its course.
    pub fn location(&self) -> Option<(Coordinate, Bearing)> {
        let middle = self.trace.get(self.trace.len() / 2)?;
        // Prefer the course the app logged; else the fix's own course; else the direction the trace moves.
        let course = self.course.or(middle.course).or_else(|| {
            let (first, last) = (self.trace.first()?, self.trace.last()?);
            (first.location.distance_to(&last.location) > 5.0)
                .then(|| first.location.bearing_to(&last.location).degrees())
        })?;
        Some((middle.location, Bearing::new(course)))
    }
}

/// How a driver went past a hotspot.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum PassOutcome {
    Warned { seconds_of_warning: f64 },
    Suppressed,
    Missed,
}

impl PassOutcome {
    pub fn was_warned(&self) -> bool {
        matches!(self, PassOutcome::Warned { .. })
    }
}

/// One uploaded event.
#[derive(Debug, Clone, PartialEq)]
pub enum EventKind {
    HardBrake(HardBrake),
    HotspotPassed {
        hotspot_id: Uuid,
        outcome: PassOutcome,
        braked_hard: bool,
    },
    WarningShown {
        hotspot_ids: Vec<Uuid>,
        speed: Option<f64>,
    },
    WarningSuppressed {
        hotspot_ids: Vec<Uuid>,
    },
    Muted,
    Unmuted,
    /// `not_helpful_hotspot` is set when the driver picked the warning that wasn't useful.
    Feedback {
        helpful: bool,
        not_helpful_hotspot: Option<Uuid>,
    },
}

/// An uploaded event: its own random id (for de-duplication) and the hour it happened.
#[derive(Debug, Clone, PartialEq)]
pub struct Event {
    pub id: Uuid,
    pub hour: DateTime<Utc>,
    pub kind: EventKind,
}

/// Anonymous counts the app sends instead of events when data sharing is off.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct UsageCounters {
    pub id: Uuid,
    pub hour: DateTime<Utc>,
    pub warnings_shown: u32,
    pub warnings_suppressed: u32,
    pub mutes: u32,
    pub hotspots_passed: u32,
}

/// Why an event was thrown away (bad GPS, a broken clock, or faked data).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Error)]
pub enum Implausible {
    #[error("the event is dated in the future")]
    FromTheFuture,
    #[error("the event is older than the upload queue keeps anything")]
    TooOld,
    #[error("the hard brake has no GPS trace")]
    NoTrace,
    #[error("a speed or deceleration is beyond what a car can do")]
    ImpossibleMotion,
    #[error("the GPS trace is scattered over too large an area")]
    ScatteredTrace,
    #[error("a coordinate isn't a real place")]
    InvalidCoordinate,
}

/// Sanity limits for uploaded events.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Plausibility {
    /// 70 m/s is about 250 km/h.
    pub maximum_speed: f64,
    /// Over 1.5 g of braking is beyond normal cars and tyres.
    pub maximum_deceleration: f64,
    /// A few fixes around a brake span at most a few hundred meters.
    pub maximum_trace_span: f64,
    /// The app drops queued batches after 30 days, so anything older is suspect.
    pub maximum_age: Duration,
}

impl Default for Plausibility {
    fn default() -> Self {
        Self {
            maximum_speed: 70.0,
            maximum_deceleration: 1.5,
            maximum_trace_span: 500.0,
            maximum_age: Duration::days(31),
        }
    }
}

impl Plausibility {
    pub fn check(&self, event: &Event, now: DateTime<Utc>) -> Result<(), Implausible> {
        // Times are rounded down to the hour, so allow an hour of slack for clock drift.
        if event.hour > now + Duration::hours(1) {
            return Err(Implausible::FromTheFuture);
        }
        if event.hour < now - self.maximum_age {
            return Err(Implausible::TooOld);
        }
        if let EventKind::HardBrake(brake) = &event.kind {
            self.check_brake(brake)?;
        }
        Ok(())
    }

    fn check_brake(&self, brake: &HardBrake) -> Result<(), Implausible> {
        if brake.trace.is_empty() {
            return Err(Implausible::NoTrace);
        }
        if brake.trace.iter().any(|point| !point.location.is_valid()) {
            return Err(Implausible::InvalidCoordinate);
        }
        let speeds = [brake.speed_before, brake.speed_after].into_iter().flatten();
        if speeds
            .chain([brake.peak_deceleration])
            .any(|value| !value.is_finite() || value < 0.0)
            || brake.speed_before.is_some_and(|speed| speed > self.maximum_speed)
            || brake.peak_deceleration > self.maximum_deceleration
        {
            return Err(Implausible::ImpossibleMotion);
        }
        let first = brake.trace[0].location;
        if brake
            .trace
            .iter()
            .any(|point| point.location.distance_to(&first) > self.maximum_trace_span)
        {
            return Err(Implausible::ScatteredTrace);
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::geo::test_support::point;

    fn brake(trace: Vec<TracePoint>) -> HardBrake {
        HardBrake {
            course: Some(10.0),
            speed_before: Some(20.0),
            speed_after: Some(8.0),
            peak_deceleration: 0.5,
            nearest_hotspot_id: None,
            was_warned: false,
            seconds_since_warning: None,
            trace,
        }
    }

    fn trace(meters: &[f64]) -> Vec<TracePoint> {
        meters
            .iter()
            .map(|&m| TracePoint {
                location: point(m, 0.0),
                course: Some(0.0),
            })
            .collect()
    }

    fn event(kind: EventKind, hour: DateTime<Utc>) -> Event {
        Event {
            id: Uuid::new_v4(),
            hour,
            kind,
        }
    }

    #[test]
    fn brake_location_is_the_middle_fix_with_the_logged_course() {
        let (location, bearing) = brake(trace(&[0.0, 20.0, 40.0])).location().expect("located");
        assert!(location.distance_to(&point(20.0, 0.0)) < 0.1);
        assert_eq!(bearing.degrees(), 10.0);
    }

    #[test]
    fn brake_without_any_course_uses_the_trace_direction() {
        let mut no_course = brake(trace(&[0.0, 20.0, 40.0]));
        no_course.course = None;
        no_course.trace.iter_mut().for_each(|point| point.course = None);
        let (_, bearing) = no_course.location().expect("located");
        assert!(bearing.difference(Bearing::new(0.0)) < 1.0);
    }

    #[test]
    fn plausibility_rejects_bad_times_and_motion() {
        let now = Utc::now();
        let rules = Plausibility::default();
        let good = brake(trace(&[0.0, 20.0]));
        assert_eq!(
            rules.check(&event(EventKind::HardBrake(good.clone()), now), now),
            Ok(())
        );
        assert_eq!(
            rules.check(&event(EventKind::Muted, now + Duration::hours(3)), now),
            Err(Implausible::FromTheFuture)
        );
        assert_eq!(
            rules.check(&event(EventKind::Muted, now - Duration::days(40)), now),
            Err(Implausible::TooOld)
        );
        assert_eq!(
            rules.check(&event(EventKind::HardBrake(brake(vec![])), now), now),
            Err(Implausible::NoTrace)
        );
        let mut too_fast = good.clone();
        too_fast.speed_before = Some(120.0);
        assert_eq!(
            rules.check(&event(EventKind::HardBrake(too_fast), now), now),
            Err(Implausible::ImpossibleMotion)
        );
        let scattered = brake(trace(&[0.0, 900.0]));
        assert_eq!(
            rules.check(&event(EventKind::HardBrake(scattered), now), now),
            Err(Implausible::ScatteredTrace)
        );
    }
}
