//! Deciding a hotspot's type from the road shape around it, the features Google's and NTUA's hard-braking
//! research relate to crash risk (ramps / merges, turning angle). See docs/MVP_USE_CASE_1.md §5.3.

use crate::geo::{Bearing, Coordinate, Polyline};
use crate::hotspot::HotspotKind;

/// A piece of road from the map.
#[derive(Debug, Clone, PartialEq)]
pub struct RoadWay {
    pub line: Polyline,
    /// A ramp or slip road (OSM `highway=*_link`) that joins or leaves another road.
    pub is_link: bool,
}

/// Classification thresholds. Starting values, to tune with real data.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Classifier {
    /// A ramp this close to the hotspot makes it a merge.
    pub merge_radius: f64,
    /// The hotspot must be this close to a road for its shape to count.
    pub road_radius: f64,
    /// Meters either side of the hotspot to measure turning over.
    pub curve_window: f64,
    /// Total turning (degrees) within the window that makes a sharp curve.
    pub curve_angle: f64,
    /// A turn tighter than this radius (meters) also makes a sharp curve.
    pub curve_radius: f64,
}

impl Default for Classifier {
    fn default() -> Self {
        Self {
            merge_radius: 60.0,
            road_radius: 30.0,
            curve_window: 100.0,
            curve_angle: 45.0,
            curve_radius: 100.0,
        }
    }
}

impl Classifier {
    /// Merge first, then curve; anything else (signals, crossings, queues) is sudden stops.
    pub fn classify(&self, location: &Coordinate, bearing: Bearing, ways: &[RoadWay]) -> HotspotKind {
        let is_near_ramp = ways
            .iter()
            .any(|way| way.is_link && way.line.project(location).distance_away <= self.merge_radius);
        if is_near_ramp {
            return HotspotKind::ShortMerge;
        }
        // The road the driver was on: the nearest non-ramp way that runs (either way) along their heading.
        let road = ways
            .iter()
            .filter(|way| !way.is_link)
            .map(|way| (way, way.line.project(location)))
            .filter(|(_, projection)| {
                projection.distance_away <= self.road_radius
                    && (projection.bearing.is_aligned(bearing, 45.0)
                        || projection
                            .bearing
                            .is_aligned(Bearing::new(bearing.degrees() + 180.0), 45.0))
            })
            .min_by(|a, b| a.1.distance_away.total_cmp(&b.1.distance_away));
        match road {
            Some((way, projection)) if self.is_curve(&way.line, projection.distance_along) => HotspotKind::SharpCurve,
            _ => HotspotKind::SuddenStop,
        }
    }

    /// Whether the road turns sharply within the window around `distance_along`.
    fn is_curve(&self, line: &Polyline, distance_along: f64) -> bool {
        let points = line.points();
        let distances = line.cumulative_distances();
        let window = (distance_along - self.curve_window)..=(distance_along + self.curve_window);
        let mut total_turn = 0.0;
        let mut tightest_radius = f64::INFINITY;
        for index in 1..points.len() - 1 {
            if !window.contains(&distances[index]) {
                continue;
            }
            let (previous, corner, next) = (points[index - 1], points[index], points[index + 1]);
            total_turn += previous.bearing_to(&corner).difference(corner.bearing_to(&next));
            tightest_radius = tightest_radius.min(circumradius(&previous, &corner, &next));
        }
        total_turn >= self.curve_angle || tightest_radius <= self.curve_radius
    }
}

/// Radius of the circle through three points (inverse of Menger curvature); infinite when they're in a line.
fn circumradius(a: &Coordinate, b: &Coordinate, c: &Coordinate) -> f64 {
    let (ab, bc, ca) = (a.distance_to(b), b.distance_to(c), c.distance_to(a));
    // Heron's formula for the triangle's area; R = abc / 4·area.
    let s = (ab + bc + ca) / 2.0;
    let area_squared = s * (s - ab) * (s - bc) * (s - ca);
    if area_squared <= 1e-6 {
        f64::INFINITY
    } else {
        ab * bc * ca / (4.0 * area_squared.sqrt())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::geo::test_support::{north_line, point};

    fn way(points: Vec<Coordinate>, is_link: bool) -> RoadWay {
        RoadWay {
            line: Polyline::new(points).expect("valid way"),
            is_link,
        }
    }

    #[test]
    fn a_straight_road_is_sudden_stops() {
        let road = RoadWay {
            line: north_line(1000.0),
            is_link: false,
        };
        assert_eq!(
            Classifier::default().classify(&point(500.0, 0.0), Bearing::new(0.0), &[road]),
            HotspotKind::SuddenStop
        );
    }

    #[test]
    fn a_right_angle_bend_is_a_sharp_curve() {
        // North 500 m, then east: a 90° bend at the hotspot.
        let bend = way(vec![point(0.0, 0.0), point(500.0, 0.0), point(500.0, 500.0)], false);
        let kind = Classifier::default().classify(&point(490.0, 0.0), Bearing::new(0.0), &[bend]);
        assert_eq!(kind, HotspotKind::SharpCurve);
    }

    #[test]
    fn a_gentle_bend_is_not_a_curve() {
        // 10° over the window, on a wide arc.
        let gentle = way(vec![point(0.0, 0.0), point(500.0, 0.0), point(1000.0, 88.0)], false);
        let kind = Classifier::default().classify(&point(500.0, 0.0), Bearing::new(0.0), &[gentle]);
        assert_eq!(kind, HotspotKind::SuddenStop);
    }

    #[test]
    fn a_ramp_joining_nearby_is_a_short_merge_even_on_a_bend() {
        let bend = way(vec![point(0.0, 0.0), point(500.0, 0.0), point(500.0, 500.0)], false);
        let ramp = way(vec![point(400.0, -80.0), point(520.0, -5.0)], true);
        let kind = Classifier::default().classify(&point(490.0, 0.0), Bearing::new(0.0), &[bend, ramp]);
        assert_eq!(kind, HotspotKind::ShortMerge);
    }

    #[test]
    fn no_map_data_means_sudden_stops() {
        assert_eq!(
            Classifier::default().classify(&point(0.0, 0.0), Bearing::new(0.0), &[]),
            HotspotKind::SuddenStop
        );
    }
}
