//! Road geometry from OpenStreetMap data imported with osm2pgsql (`just server-import-osm`).

use async_trait::async_trait;
use roadsense_application::ports::{RoadNetwork, StoreError, StoreResult};
use roadsense_domain::classify::RoadWay;
use roadsense_domain::geo::{Coordinate, Polyline};
use sqlx::Row;
use sqlx::postgres::PgPool;

/// Reads roads from osm2pgsql's `planet_osm_line` table. Returns nothing if no map has been imported.
pub struct PostgresRoadNetwork {
    pool: PgPool,
}

impl PostgresRoadNetwork {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl RoadNetwork for PostgresRoadNetwork {
    async fn ways_near(&self, location: Coordinate, radius: f64) -> StoreResult<Vec<RoadWay>> {
        let has_map: bool = sqlx::query_scalar("SELECT to_regclass('planet_osm_line') IS NOT NULL")
            .fetch_one(&self.pool)
            .await
            .map_err(|error| StoreError(error.to_string()))?;
        // No imported map: classification falls back to "sudden stops", which is still a useful warning.
        if !has_map {
            return Ok(Vec::new());
        }
        // osm2pgsql stores web-mercator (3857) geometry; compare in geography so the radius is in real meters.
        let rows = sqlx::query(
            "SELECT highway, ST_AsText(ST_Transform(way, 4326)) AS line FROM planet_osm_line \
             WHERE highway IS NOT NULL \
               AND ST_DWithin(ST_Transform(way, 4326)::geography, ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography, $3)",
        )
        .bind(location.longitude)
        .bind(location.latitude)
        .bind(radius)
        .fetch_all(&self.pool)
        .await
        .map_err(|error| StoreError(error.to_string()))?;

        Ok(rows
            .iter()
            .filter_map(|row| {
                let highway: String = row.try_get("highway").ok()?;
                let line: String = row.try_get("line").ok()?;
                Some(RoadWay {
                    line: parse_linestring(&line)?,
                    is_link: highway.ends_with("_link"),
                })
            })
            .collect())
    }
}

/// Parses `LINESTRING(lon lat,lon lat,...)` into a polyline.
fn parse_linestring(text: &str) -> Option<Polyline> {
    let inner = text.strip_prefix("LINESTRING(")?.strip_suffix(')')?;
    let points = inner
        .split(',')
        .map(|pair| {
            let mut parts = pair.split_whitespace();
            let longitude: f64 = parts.next()?.parse().ok()?;
            let latitude: f64 = parts.next()?.parse().ok()?;
            Some(Coordinate::new(latitude, longitude))
        })
        .collect::<Option<Vec<_>>>()?;
    Polyline::new(points)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_well_known_text_lines() {
        let line = parse_linestring("LINESTRING(-122.3 47.6,-122.3 47.61)").expect("parsed");
        assert_eq!(line.points().len(), 2);
        assert_eq!(line.points()[0], Coordinate::new(47.6, -122.3));
        assert!(parse_linestring("POINT(1 2)").is_none());
    }
}
