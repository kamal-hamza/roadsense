//! Turning the city's crash records into hotspots: group crashes at the same spot, then find the directions of
//! travel each group applies to from the roads there.

use std::collections::HashMap;

use crate::classify::RoadWay;
use crate::geo::{Bearing, Coordinate};

/// One reported crash: where, and the direction of travel when the record says (e.g. "NB" in the address).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CrashRecord {
    pub location: Coordinate,
    pub heading: Option<Bearing>,
}

/// Crashes close enough together to be one place.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CrashCluster {
    /// The average position of its crashes.
    pub center: Coordinate,
    pub crashes: u32,
    /// The direction most of its crashes were going, when most records say.
    pub heading: Option<Bearing>,
}

/// How crashes are grouped, and how many make a place worth warning about.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CrashClustering {
    /// Crashes within this many meters of a group's center join it.
    pub radius: f64,
    /// Groups with fewer crashes are dropped.
    pub minimum_crashes: u32,
    /// Roads this close to a group's center give it its directions of travel.
    pub road_radius: f64,
}

impl Default for CrashClustering {
    fn default() -> Self {
        // Five crashes matches the five drivers a driver-reported hotspot needs.
        Self {
            radius: 30.0,
            minimum_crashes: 5,
            road_radius: 20.0,
        }
    }
}

/// A group being built, with the headings its crashes reported.
struct Growing {
    latitude_sum: f64,
    longitude_sum: f64,
    crashes: u32,
    headings: HashMap<u16, u32>,
}

impl Growing {
    fn center(&self) -> Coordinate {
        let count = f64::from(self.crashes);
        Coordinate::new(self.latitude_sum / count, self.longitude_sum / count)
    }
}

impl CrashClustering {
    /// Groups crashes within `radius` of each other and keeps groups with at least `minimum_crashes`.
    /// Roughly O(n): each crash only looks at groups in the neighbouring grid cells.
    pub fn cluster(&self, records: &[CrashRecord]) -> Vec<CrashCluster> {
        // A grid of radius-sized cells, so a crash only checks groups in its own and the eight cells around it.
        let cell_degrees = self.radius / 111_320.0;
        let cell = |point: &Coordinate| {
            (
                (point.latitude / cell_degrees).floor() as i64,
                (point.longitude / cell_degrees).floor() as i64,
            )
        };
        let mut groups: Vec<Growing> = Vec::new();
        let mut grid: HashMap<(i64, i64), Vec<usize>> = HashMap::new();

        for record in records {
            let (row, column) = cell(&record.location);
            let nearest = (row - 1..=row + 1)
                .flat_map(|r| (column - 1..=column + 1).map(move |c| (r, c)))
                .filter_map(|key| grid.get(&key))
                .flatten()
                .map(|&index| (index, groups[index].center().distance_to(&record.location)))
                .filter(|(_, distance)| *distance <= self.radius)
                .min_by(|a, b| a.1.total_cmp(&b.1));

            let index = match nearest {
                Some((index, _)) => index,
                None => {
                    groups.push(Growing {
                        latitude_sum: 0.0,
                        longitude_sum: 0.0,
                        crashes: 0,
                        headings: HashMap::new(),
                    });
                    grid.entry((row, column)).or_default().push(groups.len() - 1);
                    groups.len() - 1
                }
            };
            let group = &mut groups[index];
            group.latitude_sum += record.location.latitude;
            group.longitude_sum += record.location.longitude;
            group.crashes += 1;
            if let Some(heading) = record.heading {
                *group.headings.entry(heading.degrees().round() as u16).or_default() += 1;
            }
        }

        groups
            .into_iter()
            .filter(|group| group.crashes >= self.minimum_crashes)
            .map(|group| CrashCluster {
                center: group.center(),
                crashes: group.crashes,
                // Only trust a direction most of the group's records agree on.
                heading: group
                    .headings
                    .iter()
                    .max_by_key(|(_, count)| **count)
                    .filter(|(_, count)| **count * 2 > group.crashes)
                    .map(|(degrees, _)| Bearing::new(f64::from(*degrees))),
            })
            .collect()
    }

    /// The directions of travel through `cluster`: both ways along each road within `road_radius`, with
    /// near-duplicates dropped. With a known heading, only the directions within 60° of it.
    pub fn travel_directions(&self, cluster: &CrashCluster, ways: &[RoadWay]) -> Vec<Bearing> {
        let mut directions: Vec<Bearing> = Vec::new();
        for way in ways {
            let projection = way.line.project(&cluster.center);
            if projection.distance_away > self.road_radius {
                continue;
            }
            for bearing in [projection.bearing, Bearing::new(projection.bearing.degrees() + 180.0)] {
                // Roads are split where they cross, so the same direction shows up from several ways.
                let is_new = directions.iter().all(|known| !known.is_aligned(bearing, 30.0));
                let matches_heading = cluster.heading.is_none_or(|heading| heading.is_aligned(bearing, 60.0));
                if is_new && matches_heading {
                    directions.push(bearing);
                }
            }
        }
        directions
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::geo::Polyline;
    use crate::geo::test_support::{ORIGIN, point};

    fn crashes_at(location: Coordinate, count: usize, heading: Option<f64>) -> Vec<CrashRecord> {
        vec![
            CrashRecord {
                location,
                heading: heading.map(Bearing::new),
            };
            count
        ]
    }

    fn road(from: Coordinate, to: Coordinate) -> RoadWay {
        RoadWay {
            line: Polyline::new(vec![from, to]).unwrap(),
            is_link: false,
        }
    }

    #[test]
    fn groups_nearby_crashes_and_drops_small_groups() {
        let mut records = crashes_at(point(0.0, 0.0), 3, None);
        records.extend(crashes_at(point(10.0, 5.0), 3, None));
        records.extend(crashes_at(point(500.0, 0.0), 4, None));

        let clusters = CrashClustering::default().cluster(&records);

        assert_eq!(clusters.len(), 1);
        assert_eq!(clusters[0].crashes, 6);
        assert!(clusters[0].center.distance_to(&point(5.0, 2.5)) < 1.0);
    }

    #[test]
    fn keeps_a_heading_only_when_most_crashes_agree() {
        let mut agreed = crashes_at(ORIGIN, 4, Some(0.0));
        agreed.extend(crashes_at(ORIGIN, 1, None));
        let mut split = crashes_at(point(1000.0, 0.0), 3, Some(0.0));
        split.extend(crashes_at(point(1000.0, 0.0), 3, Some(180.0)));

        let clustering = CrashClustering::default();
        let agreed = clustering.cluster(&agreed);
        let split = clustering.cluster(&split);

        assert_eq!(agreed[0].heading, Some(Bearing::new(0.0)));
        assert_eq!(split[0].heading, None);
    }

    #[test]
    fn an_intersection_gets_four_directions_and_a_signed_heading_one() {
        // A north-south road split at the crossing, and an east-west road through it.
        let ways = [
            road(point(-200.0, 0.0), ORIGIN),
            road(ORIGIN, point(200.0, 0.0)),
            road(point(0.0, -200.0), point(0.0, 200.0)),
        ];
        let mut cluster = CrashCluster {
            center: ORIGIN,
            crashes: 6,
            heading: None,
        };
        let clustering = CrashClustering::default();

        let mut all: Vec<i64> = clustering
            .travel_directions(&cluster, &ways)
            .iter()
            .map(|b| b.degrees().round() as i64)
            .collect();
        all.sort_unstable();
        cluster.heading = Some(Bearing::new(180.0));
        let southbound = clustering.travel_directions(&cluster, &ways);

        assert_eq!(all, vec![0, 90, 180, 270]);
        assert_eq!(southbound.len(), 1);
        assert!(southbound[0].difference(Bearing::new(180.0)) < 1.0);
    }

    #[test]
    fn no_road_nearby_means_no_directions() {
        let far = [road(point(0.0, 100.0), point(200.0, 100.0))];
        let cluster = CrashCluster {
            center: ORIGIN,
            crashes: 5,
            heading: None,
        };

        assert!(CrashClustering::default().travel_directions(&cluster, &far).is_empty());
    }
}
