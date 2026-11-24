use std::sync::Arc;

use roadsense_domain::classify::Classifier;
use roadsense_domain::collisions::{CrashClustering, CrashRecord};
use roadsense_domain::hotspot::Hotspot;

use crate::ports::{Clock, HotspotRepository, RoadNetwork, StoreResult};

/// What an import did, for the command's output and tests.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct ImportReport {
    pub crashes: u32,
    /// Places with enough crashes to become hotspots.
    pub places: u32,
    /// Places dropped because no mapped road runs through them.
    pub places_without_roads: u32,
    pub hotspots: u32,
}

/// Replaces the hotspots from the city's collision records with ones built from `records`.
pub struct ImportCityCollisions {
    pub hotspots: Arc<dyn HotspotRepository>,
    pub roads: Arc<dyn RoadNetwork>,
    pub clock: Arc<dyn Clock>,
    pub clustering: CrashClustering,
    pub classifier: Classifier,
}

/// How far around a place to fetch roads: enough for the classifier to see curves and ramps.
const ROAD_SEARCH_RADIUS: f64 = 150.0;

impl ImportCityCollisions {
    /// Groups the crashes, gives each group a hotspot per direction of travel, and swaps them in for the
    /// previous import. Driver-reported hotspots are left alone.
    pub async fn execute(&self, records: &[CrashRecord]) -> StoreResult<ImportReport> {
        let now = self.clock.now();
        let places = self.clustering.cluster(records);
        let mut report = ImportReport {
            crashes: u32::try_from(records.len()).unwrap_or(u32::MAX),
            places: u32::try_from(places.len()).unwrap_or(u32::MAX),
            ..ImportReport::default()
        };

        let mut hotspots = Vec::new();
        for place in &places {
            let ways = self.roads.ways_near(place.center, ROAD_SEARCH_RADIUS).await?;
            let directions = self.clustering.travel_directions(place, &ways);
            if directions.is_empty() {
                report.places_without_roads += 1;
            }
            for bearing in directions {
                // The road's shape decides the kind, the same way it does for driver-reported hotspots.
                let kind = self.classifier.classify(&place.center, bearing, &ways);
                hotspots.push(Hotspot::from_collisions(
                    place.center,
                    bearing,
                    kind,
                    place.crashes,
                    now,
                ));
            }
        }
        report.hotspots = u32::try_from(hotspots.len()).unwrap_or(u32::MAX);
        self.hotspots.replace_city_collision_hotspots(&hotspots).await?;
        Ok(report)
    }
}
