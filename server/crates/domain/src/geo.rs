//! Small-scale geometry on WGS84 coordinates, accurate over the tens to hundreds of meters routes work at.

/// Mean Earth radius in meters, the same value the iOS app uses.
const EARTH_RADIUS: f64 = 6_371_000.0;

/// A latitude/longitude pair, in degrees.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Coordinate {
    pub latitude: f64,
    pub longitude: f64,
}

impl Coordinate {
    pub fn new(latitude: f64, longitude: f64) -> Self {
        Self { latitude, longitude }
    }

    /// Whether this is a real place on Earth.
    pub fn is_valid(&self) -> bool {
        self.latitude.is_finite()
            && self.longitude.is_finite()
            && (-90.0..=90.0).contains(&self.latitude)
            && (-180.0..=180.0).contains(&self.longitude)
    }

    /// Great-circle distance to `other`, in meters (haversine formula).
    pub fn distance_to(&self, other: &Coordinate) -> f64 {
        let lat1 = self.latitude.to_radians();
        let lat2 = other.latitude.to_radians();
        let delta_lat = lat2 - lat1;
        let delta_lon = (other.longitude - self.longitude).to_radians();
        let haversine = (delta_lat / 2.0).sin().powi(2) + lat1.cos() * lat2.cos() * (delta_lon / 2.0).sin().powi(2);
        // min(1, …) guards against rounding pushing asin out of range.
        2.0 * EARTH_RADIUS * haversine.sqrt().min(1.0).asin()
    }

    /// Initial great-circle bearing toward `other`.
    pub fn bearing_to(&self, other: &Coordinate) -> Bearing {
        let lat1 = self.latitude.to_radians();
        let lat2 = other.latitude.to_radians();
        let delta_lon = (other.longitude - self.longitude).to_radians();
        let y = delta_lon.sin() * lat2.cos();
        let x = lat1.cos() * lat2.sin() - lat1.sin() * lat2.cos() * delta_lon.cos();
        Bearing::new(y.atan2(x).to_degrees())
    }

    /// The coordinate `distance` meters away toward `bearing`.
    pub fn offset(&self, distance: f64, bearing: Bearing) -> Coordinate {
        let angular = distance / EARTH_RADIUS;
        let heading = bearing.degrees().to_radians();
        let lat1 = self.latitude.to_radians();
        let lon1 = self.longitude.to_radians();
        // Destination-point formula on a sphere.
        let lat2 = (lat1.sin() * angular.cos() + lat1.cos() * angular.sin() * heading.cos()).asin();
        let lon2 = lon1 + (heading.sin() * angular.sin() * lat1.cos()).atan2(angular.cos() - lat1.sin() * lat2.sin());
        Coordinate::new(lat2.to_degrees(), lon2.to_degrees())
    }

    /// This point in meters east (x) and north (y) of `origin` on a flat local map.
    fn local_offset(&self, origin: &Coordinate) -> (f64, f64) {
        let meters_per_degree = EARTH_RADIUS * std::f64::consts::PI / 180.0;
        // Equirectangular projection: fine within a few km and much cheaper than great circles.
        let x = (self.longitude - origin.longitude) * meters_per_degree * origin.latitude.to_radians().cos();
        let y = (self.latitude - origin.latitude) * meters_per_degree;
        (x, y)
    }
}

/// A compass direction in degrees clockwise from true north, always in `0..360`.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Bearing(f64);

impl Bearing {
    /// Wraps any angle into `0..360`.
    pub fn new(degrees: f64) -> Self {
        let wrapped = degrees.rem_euclid(360.0);
        // rem_euclid can round a tiny negative up to exactly 360.
        Self(if wrapped >= 360.0 { 0.0 } else { wrapped })
    }

    pub fn degrees(&self) -> f64 {
        self.0
    }

    /// The smallest angle to `other`, from 0 to 180 degrees.
    pub fn difference(&self, other: Bearing) -> f64 {
        let raw = (self.0 - other.0).abs();
        // 350° and 10° are 20° apart, not 340°.
        raw.min(360.0 - raw)
    }

    /// Whether `other` points the same way, within `tolerance` degrees either side.
    pub fn is_aligned(&self, other: Bearing, tolerance: f64) -> bool {
        self.difference(other) <= tolerance
    }
}

/// Where a point falls relative to a polyline.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Projection {
    /// Meters from the start of the line to the closest point on it.
    pub distance_along: f64,
    /// Meters from the point to the line.
    pub distance_away: f64,
    /// Direction of the line at that closest point.
    pub bearing: Bearing,
}

/// A line through coordinates, such as a driving route or a road.
#[derive(Debug, Clone, PartialEq)]
pub struct Polyline {
    points: Vec<Coordinate>,
    /// Distance from the start to each point.
    cumulative: Vec<f64>,
}

impl Polyline {
    /// A polyline through `points`, dropping repeats; `None` if fewer than two distinct points remain.
    pub fn new(points: Vec<Coordinate>) -> Option<Self> {
        let mut distinct: Vec<Coordinate> = Vec::with_capacity(points.len());
        for point in points {
            if distinct.last() != Some(&point) {
                distinct.push(point);
            }
        }
        if distinct.len() < 2 || distinct.iter().any(|point| !point.is_valid()) {
            return None;
        }
        let mut cumulative = vec![0.0];
        for pair in distinct.windows(2) {
            let last = cumulative.last().copied().unwrap_or(0.0);
            cumulative.push(last + pair[0].distance_to(&pair[1]));
        }
        Some(Self {
            points: distinct,
            cumulative,
        })
    }

    pub fn points(&self) -> &[Coordinate] {
        &self.points
    }

    /// Total length in meters.
    pub fn length(&self) -> f64 {
        self.cumulative.last().copied().unwrap_or(0.0)
    }

    /// Meters from the start to each point, parallel to `points()`.
    pub fn cumulative_distances(&self) -> &[f64] {
        &self.cumulative
    }

    /// The closest point on the line to `point`. O(n) in the number of segments.
    pub fn project(&self, point: &Coordinate) -> Projection {
        let mut best: Option<Projection> = None;
        for (index, pair) in self.points.windows(2).enumerate() {
            let (start, end) = (pair[0], pair[1]);
            let (end_x, end_y) = end.local_offset(&start);
            let (point_x, point_y) = point.local_offset(&start);
            let length_squared = end_x * end_x + end_y * end_y;
            // Dot product gives the fraction along the segment; clamp so we stay between the endpoints.
            let fraction = if length_squared > 0.0 {
                ((point_x * end_x + point_y * end_y) / length_squared).clamp(0.0, 1.0)
            } else {
                0.0
            };
            let away = ((point_x - fraction * end_x).powi(2) + (point_y - fraction * end_y).powi(2)).sqrt();
            if best.is_none_or(|current| away < current.distance_away) {
                let segment_length = self.cumulative[index + 1] - self.cumulative[index];
                best = Some(Projection {
                    distance_along: self.cumulative[index] + fraction * segment_length,
                    distance_away: away,
                    bearing: start.bearing_to(&end),
                });
            }
        }
        // `new` guarantees at least one segment, so there's always a best.
        best.unwrap_or(Projection {
            distance_along: 0.0,
            distance_away: f64::INFINITY,
            bearing: Bearing::new(0.0),
        })
    }
}

#[cfg(test)]
pub(crate) mod test_support {
    use super::*;

    pub const ORIGIN: Coordinate = Coordinate {
        latitude: 47.6,
        longitude: -122.3,
    };

    /// A point `meters` north of the origin, shifted `east` meters sideways.
    pub fn point(meters: f64, east: f64) -> Coordinate {
        let along = ORIGIN.offset(meters, Bearing::new(if meters >= 0.0 { 0.0 } else { 180.0 }));
        if east == 0.0 {
            along
        } else {
            along.offset(east.abs(), Bearing::new(if east > 0.0 { 90.0 } else { 270.0 }))
        }
    }

    /// A straight road north from the origin, with a point every 100 m.
    pub fn north_line(length: f64) -> Polyline {
        let points = (0..=(length / 100.0) as usize)
            .map(|step| point(step as f64 * 100.0, 0.0))
            .collect();
        Polyline::new(points).expect("valid line")
    }
}

#[cfg(test)]
mod tests {
    use super::test_support::*;
    use super::*;

    #[test]
    fn bearing_wraps_and_measures_the_short_way_round() {
        assert_eq!(Bearing::new(370.0).degrees(), 10.0);
        assert_eq!(Bearing::new(-10.0).degrees(), 350.0);
        assert_eq!(Bearing::new(350.0).difference(Bearing::new(10.0)), 20.0);
        assert!(Bearing::new(0.0).is_aligned(Bearing::new(45.0), 45.0));
        assert!(!Bearing::new(0.0).is_aligned(Bearing::new(46.0), 45.0));
    }

    #[test]
    fn offset_and_bearing_round_trip() {
        for degrees in [0.0, 45.0, 90.0, 180.0, 270.0] {
            let target = ORIGIN.offset(500.0, Bearing::new(degrees));
            assert!((ORIGIN.distance_to(&target) - 500.0).abs() < 0.5);
            assert!(ORIGIN.bearing_to(&target).difference(Bearing::new(degrees)) < 0.1);
        }
    }

    #[test]
    fn polyline_projects_a_point_beside_it() {
        let line = north_line(2000.0);
        let projection = line.project(&point(750.0, 20.0));
        assert!((projection.distance_along - 750.0).abs() < 1.0);
        assert!((projection.distance_away - 20.0).abs() < 1.0);
        assert!(projection.bearing.difference(Bearing::new(0.0)) < 0.1);
        assert!((line.length() - 2000.0).abs() < 1.0);
    }

    #[test]
    fn polyline_needs_two_distinct_valid_points() {
        assert!(Polyline::new(vec![ORIGIN, ORIGIN]).is_none());
        assert!(Polyline::new(vec![ORIGIN, Coordinate::new(95.0, 0.0)]).is_none());
        assert!(Polyline::new(vec![ORIGIN, point(100.0, 0.0)]).is_some());
    }
}
