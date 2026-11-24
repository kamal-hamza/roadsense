//! Imports Seattle's collision records as hotspots: `import-collisions <collisions.geojson>`, with DATABASE_URL
//! set. `just server-import-collisions` downloads the records and runs this.

use std::error::Error;
use std::sync::Arc;

use roadsense_application::ports::SystemClock;
use roadsense_application::use_cases::ImportCityCollisions;
use roadsense_domain::classify::Classifier;
use roadsense_domain::collisions::CrashClustering;
use roadsense_infrastructure::city_collisions;
use roadsense_infrastructure::osm::PostgresRoadNetwork;
use roadsense_infrastructure::postgres::PostgresStore;

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    let path = std::env::args()
        .nth(1)
        .ok_or("usage: import-collisions <collisions.geojson>")?;
    let records = city_collisions::parse(&std::fs::read_to_string(&path)?)?;
    // The import replaces the previous one, so an empty or failed download must not wipe it.
    if records.is_empty() {
        return Err(format!("{path} has no crash records; keeping the current hotspots").into());
    }

    let url = std::env::var("DATABASE_URL").map_err(|_| "set DATABASE_URL")?;
    let store = Arc::new(PostgresStore::connect(&url).await?);
    let roads = Arc::new(PostgresRoadNetwork::new(store.pool().clone()));
    // Directions come from the road map; without it every place would be dropped.
    if !roads.has_map().await? {
        return Err("no road map in this database; run `just server-import-osm` against it first".into());
    }

    let import = ImportCityCollisions {
        hotspots: store,
        roads,
        clock: Arc::new(SystemClock),
        clustering: CrashClustering::default(),
        classifier: Classifier::default(),
    };
    let report = import.execute(&records).await?;
    println!(
        "{} crashes -> {} places ({} with no mapped road, skipped) -> {} hotspots",
        report.crashes, report.places, report.places_without_roads, report.hotspots
    );
    Ok(())
}
