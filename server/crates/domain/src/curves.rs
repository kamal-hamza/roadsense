//! Sharp turns as evidence that a hotspot is a curve. The road map decides a hotspot's type first; drivers
//! cornering hard through it can show the map missed a bend (a coarse OSM line, a tight lane shift).

use crate::classify::RoadWay;
use crate::events::{SharpTurn, TracePoint};
use crate::geo::Bearing;
use crate::hotspot::Hotspot;

/// When a sharp turn supports a hotspot being a curve.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CurveEvidence {
    /// The hotspot must be this close to the turn. Drivers brake before a bend and corner in it, so the two
    /// are near each other but not on the same spot.
    pub hotspot_radius: f64,
    /// Degrees the car's direction near the hotspot may differ from the hotspot's.
    pub heading_tolerance: f64,
    /// Every fix of the turn must be this close to one road for the turn to count as following it.
    pub road_radius: f64,
    /// Fewer fixes than this can't show the car stayed on one road.
    pub minimum_fixes: usize,
}

impl Default for CurveEvidence {
    fn default() -> Self {
        Self {
            hotspot_radius: 100.0,
            heading_tolerance: 60.0,
            road_radius: 15.0,
            minimum_fixes: 3,
        }
    }
}

impl CurveEvidence {
    /// The hotspot this turn supports: the closest one within `hotspot_radius` of the turn's path whose direction
    /// matches the car's where it passed it.
    pub fn supported<'a>(&self, turn: &SharpTurn, hotspots: &'a [Hotspot]) -> Option<&'a Hotspot> {
        hotspots
            .iter()
            .filter_map(|hotspot| {
                // The fix closest to the hotspot, and which way the car was going there.
                let (index, closest) = turn.trace.iter().enumerate().min_by(|a, b| {
                    let distance = |point: &TracePoint| point.location.distance_to(&hotspot.location);
                    distance(a.1).total_cmp(&distance(b.1))
                })?;
                let distance = closest.location.distance_to(&hotspot.location);
                let heading = self.heading_at(turn, index)?;
                (distance <= self.hotspot_radius && heading.is_aligned(hotspot.bearing, self.heading_tolerance))
                    .then_some((hotspot, distance))
            })
            .min_by(|a, b| a.1.total_cmp(&b.1))
            .map(|(hotspot, _)| hotspot)
    }

    /// Whether the car stayed on one road through the turn: a bend, not turning off at a junction. Roads are
    /// split where they cross, so turning onto another street leaves the first road's line.
    pub fn follows_one_road(&self, turn: &SharpTurn, ways: &[RoadWay]) -> bool {
        turn.trace.len() >= self.minimum_fixes
            && ways.iter().filter(|way| !way.is_link).any(|way| {
                turn.trace
                    .iter()
                    .all(|point| way.line.project(&point.location).distance_away <= self.road_radius)
            })
    }

    /// The fix's own course, or else the direction from the fix before it to the fix after it.
    fn heading_at(&self, turn: &SharpTurn, index: usize) -> Option<Bearing> {
        if let Some(course) = turn.trace[index].course {
            return Some(Bearing::new(course));
        }
        let before = turn.trace[index.saturating_sub(1)].location;
        let after = turn.trace[(index + 1).min(turn.trace.len() - 1)].location;
        (before.distance_to(&after) > 1.0).then(|| before.bearing_to(&after))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::geo::test_support::{ORIGIN, point};
    use crate::geo::{Coordinate, Polyline};
    use crate::hotspot::HotspotKind;
    use chrono::Utc;

    /// North for 100 m, then bending to the east: fixes along it, each with the road's direction there.
    fn bend() -> Vec<(Coordinate, f64)> {
        let corner = point(100.0, 0.0);
        vec![
            (point(60.0, 0.0), 0.0),
            (point(90.0, 0.0), 10.0),
            (corner.offset(20.0, Bearing::new(45.0)), 45.0),
            (corner.offset(50.0, Bearing::new(80.0)), 80.0),
        ]
    }

    fn turn(fixes: &[(Coordinate, f64)]) -> SharpTurn {
        SharpTurn {
            peak_lateral_acceleration: 0.4,
            trace: fixes
                .iter()
                .map(|&(location, course)| TracePoint {
                    location,
                    course: Some(course),
                })
                .collect(),
        }
    }

    fn hotspot(at: Coordinate, bearing: f64) -> Hotspot {
        Hotspot::candidate(at, Bearing::new(bearing), HotspotKind::SuddenStop, Utc::now())
    }

    fn way(points: Vec<Coordinate>) -> RoadWay {
        RoadWay {
            line: Polyline::new(points).unwrap(),
            is_link: false,
        }
    }

    #[test]
    fn supports_the_nearest_hotspot_going_the_same_way() {
        let hotspots = [
            hotspot(point(70.0, 0.0), 0.0),
            // Same place, other direction.
            hotspot(point(80.0, 0.0), 180.0),
            hotspot(point(600.0, 0.0), 0.0),
        ];

        let supported = CurveEvidence::default().supported(&turn(&bend()), &hotspots);

        assert_eq!(supported.map(|h| h.id), Some(hotspots[0].id));
    }

    #[test]
    fn a_bend_follows_one_road_but_a_turn_at_a_junction_does_not() {
        let corner = point(100.0, 0.0);
        // One way that bends, versus two streets meeting at the corner.
        let bending = [way(vec![
            ORIGIN,
            point(90.0, 0.0),
            corner.offset(20.0, Bearing::new(45.0)),
            corner.offset(50.0, Bearing::new(80.0)),
            corner.offset(200.0, Bearing::new(85.0)),
        ])];
        let junction = [
            way(vec![ORIGIN, corner, point(300.0, 0.0)]),
            way(vec![
                corner.offset(-200.0, Bearing::new(90.0)),
                corner.offset(200.0, Bearing::new(90.0)),
            ]),
        ];
        let right_turn = turn(&[
            (point(60.0, 0.0), 0.0),
            (point(95.0, 0.0), 0.0),
            (corner.offset(30.0, Bearing::new(90.0)), 90.0),
            (corner.offset(60.0, Bearing::new(90.0)), 90.0),
        ]);
        let rules = CurveEvidence::default();

        assert!(rules.follows_one_road(&turn(&bend()), &bending));
        assert!(!rules.follows_one_road(&right_turn, &junction));
        assert!(!rules.follows_one_road(&turn(&bend()[..2]), &bending), "too few fixes");
    }
}
