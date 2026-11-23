//! Choosing which hotspots to warn about on a route (activity diagram 2, backend side).

use crate::geo::Polyline;
use crate::hotspot::{CountedHotspot, HotspotStatus, RouteHotspot};
use crate::rules::{Consensus, HotspotMatch};

/// The route lookup rules: corridor, direction, consensus, and merging close hotspots.
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct RouteLookup {
    pub matching: HotspotMatch,
    pub consensus: Consensus,
    /// Hotspots closer than this along the route become one warning.
    pub merge_distance: MergeDistance,
}

/// Meters between hotspots below which they're merged; 50 m by default.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct MergeDistance(pub f64);

impl Default for MergeDistance {
    fn default() -> Self {
        Self(50.0)
    }
}

impl RouteLookup {
    /// Active hotspots on `route` going its way, with enough drivers, merged and sorted by distance along it.
    /// O(h × s) for h candidates and s route segments.
    pub fn select(&self, route: &Polyline, candidates: Vec<CountedHotspot>) -> Vec<RouteHotspot> {
        let mut on_route: Vec<RouteHotspot> = candidates
            .into_iter()
            .filter(|counted| {
                counted.hotspot.status == HotspotStatus::Active && self.consensus.is_met(counted.driver_count)
            })
            .filter_map(|counted| {
                let projection = route.project(&counted.hotspot.location);
                // On the road (within the corridor) and facing the way the route goes there.
                let is_on_route = projection.distance_away <= self.matching.radius
                    && counted
                        .hotspot
                        .bearing
                        .is_aligned(projection.bearing, self.matching.heading_tolerance);
                is_on_route.then_some(RouteHotspot {
                    hotspot: counted.hotspot,
                    driver_count: counted.driver_count,
                    distance_along_route: projection.distance_along,
                })
            })
            .collect();
        on_route.sort_by(|a, b| a.distance_along_route.total_cmp(&b.distance_along_route));
        self.merge(on_route)
    }

    /// Keeps one hotspot per cluster closer than the merge distance: the one most drivers flagged.
    fn merge(&self, sorted: Vec<RouteHotspot>) -> Vec<RouteHotspot> {
        let mut merged: Vec<RouteHotspot> = Vec::with_capacity(sorted.len());
        for hotspot in sorted {
            match merged.last_mut() {
                Some(last) if hotspot.distance_along_route - last.distance_along_route < self.merge_distance.0 => {
                    if hotspot.driver_count > last.driver_count {
                        *last = hotspot;
                    }
                }
                _ => merged.push(hotspot),
            }
        }
        merged
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::geo::Bearing;
    use crate::geo::test_support::{north_line, point};
    use crate::hotspot::{Hotspot, HotspotKind};
    use chrono::Utc;

    fn counted(meters: f64, east: f64, bearing: f64, status: HotspotStatus, drivers: u32) -> CountedHotspot {
        let mut hotspot = Hotspot::candidate(
            point(meters, east),
            Bearing::new(bearing),
            HotspotKind::SuddenStop,
            Utc::now(),
        );
        hotspot.status = status;
        CountedHotspot {
            hotspot,
            driver_count: drivers,
        }
    }

    #[test]
    fn keeps_active_hotspots_on_the_route_going_its_way_in_order() {
        let route = north_line(2000.0);
        let selected = RouteLookup::default().select(
            &route,
            vec![
                counted(1500.0, 0.0, 0.0, HotspotStatus::Active, 6),
                counted(300.0, 10.0, 10.0, HotspotStatus::Active, 9),
                counted(800.0, 0.0, 180.0, HotspotStatus::Active, 9),
                counted(1000.0, 60.0, 0.0, HotspotStatus::Active, 9),
                counted(1200.0, 0.0, 0.0, HotspotStatus::Candidate, 9),
                counted(1700.0, 0.0, 0.0, HotspotStatus::Active, 4),
            ],
        );
        let distances: Vec<i64> = selected.iter().map(|h| h.distance_along_route.round() as i64).collect();
        assert_eq!(distances, vec![300, 1500]);
    }

    #[test]
    fn merges_hotspots_under_50_m_apart_keeping_the_most_flagged() {
        let route = north_line(2000.0);
        let selected = RouteLookup::default().select(
            &route,
            vec![
                counted(1000.0, 0.0, 0.0, HotspotStatus::Active, 6),
                counted(1030.0, 0.0, 0.0, HotspotStatus::Active, 12),
                counted(1100.0, 0.0, 0.0, HotspotStatus::Active, 5),
            ],
        );
        let drivers: Vec<u32> = selected.iter().map(|h| h.driver_count).collect();
        assert_eq!(drivers, vec![12, 5]);
    }
}
