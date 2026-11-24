//! PostgreSQL + PostGIS storage. Queries are checked at runtime, so builds don't need a database.

use std::fmt::Write as _;

use async_trait::async_trait;
use chrono::{DateTime, Duration, Utc};
use roadsense_application::ports::{
    DeviceRepository, EventRepository, HealthCheck, HotspotRepository, StoreError, StoreResult,
};
use roadsense_domain::events::{Event, EventKind, UsageCounters};
use roadsense_domain::geo::{Bearing, Coordinate, Polyline};
use roadsense_domain::hotspot::{CountedHotspot, Hotspot, HotspotKind, HotspotStatus};
use roadsense_domain::metrics::PassCounts;
use sqlx::postgres::{PgPool, PgPoolOptions, PgRow};
use sqlx::{Executor, Row};
use uuid::Uuid;

use crate::codes::{
    event_code, kind_code, kind_from_code, outcome_code, source_code, source_from_code, status_code, status_from_code,
};

/// Embedded migrations from server/migrations.
static MIGRATOR: sqlx::migrate::Migrator = sqlx::migrate!("../../migrations");

/// Columns selected for every hotspot query, in the order `hotspot_from_row` reads them.
const HOTSPOT_COLUMNS: &str = "h.id, h.kind, h.status, ST_Y(h.location::geometry) AS latitude, \
    ST_X(h.location::geometry) AS longitude, h.bearing, h.created_at, h.flagged_for_review, h.source, \
    h.reported_crashes";

/// The PostGIS-backed store; implements every storage port.
#[derive(Clone)]
pub struct PostgresStore {
    pool: PgPool,
}

impl PostgresStore {
    /// Connects, keeping RoadSense's tables in the `roadsense` schema, and brings the schema up to date.
    pub async fn connect(url: &str) -> StoreResult<Self> {
        Self::with_pool(pool_in_schema(url, APP_SCHEMA, 5).await?).await
    }

    /// Uses an existing pool (tests pass one scoped to their own schema) and runs migrations.
    pub async fn with_pool(pool: PgPool) -> StoreResult<Self> {
        MIGRATOR
            .run(&pool)
            .await
            .map_err(|error| StoreError(error.to_string()))?;
        Ok(Self { pool })
    }

    pub fn pool(&self) -> &PgPool {
        &self.pool
    }
}

fn to_store_error(error: sqlx::Error) -> StoreError {
    StoreError(error.to_string())
}

fn hotspot_from_row(row: &PgRow) -> StoreResult<Hotspot> {
    let read = |error: sqlx::Error| StoreError(error.to_string());
    Ok(Hotspot {
        id: row.try_get("id").map_err(read)?,
        kind: kind_from_code(row.try_get("kind").map_err(read)?),
        status: status_from_code(row.try_get("status").map_err(read)?),
        location: Coordinate::new(
            row.try_get("latitude").map_err(read)?,
            row.try_get("longitude").map_err(read)?,
        ),
        bearing: Bearing::new(row.try_get("bearing").map_err(read)?),
        created_at: row.try_get("created_at").map_err(read)?,
        flagged_for_review: row.try_get("flagged_for_review").map_err(read)?,
        source: source_from_code(
            row.try_get("source").map_err(read)?,
            row.try_get("reported_crashes").map_err(read)?,
        ),
    })
}

fn counted_from_row(row: &PgRow) -> StoreResult<CountedHotspot> {
    let drivers: i64 = row.try_get("drivers").map_err(to_store_error)?;
    Ok(CountedHotspot {
        hotspot: hotspot_from_row(row)?,
        driver_count: u32::try_from(drivers).unwrap_or(u32::MAX),
    })
}

/// The route as well-known text, e.g. `SRID=4326;LINESTRING(lon lat, lon lat)`.
fn route_wkt(route: &Polyline) -> String {
    let mut text = String::from("SRID=4326;LINESTRING(");
    for (index, point) in route.points().iter().enumerate() {
        let separator = if index == 0 { "" } else { "," };
        // Writing to a String can't fail.
        let _ = write!(text, "{separator}{} {}", point.longitude, point.latitude);
    }
    text.push(')');
    text
}

fn to_u32(value: i64) -> u32 {
    u32::try_from(value.max(0)).unwrap_or(u32::MAX)
}

#[async_trait]
impl HealthCheck for PostgresStore {
    async fn check(&self) -> StoreResult<()> {
        sqlx::query("SELECT 1")
            .execute(&self.pool)
            .await
            .map_err(to_store_error)?;
        Ok(())
    }
}

#[async_trait]
impl DeviceRepository for PostgresStore {
    async fn register(&self, id: Uuid, at: DateTime<Utc>) -> StoreResult<()> {
        sqlx::query("INSERT INTO devices (id, registered_at) VALUES ($1, $2) ON CONFLICT (id) DO NOTHING")
            .bind(id)
            .bind(at)
            .execute(&self.pool)
            .await
            .map_err(to_store_error)?;
        Ok(())
    }

    async fn exists(&self, id: Uuid) -> StoreResult<bool> {
        sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM devices WHERE id = $1)")
            .bind(id)
            .fetch_one(&self.pool)
            .await
            .map_err(to_store_error)
    }

    async fn record_activity(&self, id: Uuid, at: DateTime<Utc>) -> StoreResult<()> {
        sqlx::query("INSERT INTO device_activity (device_id, day) VALUES ($1, $2) ON CONFLICT DO NOTHING")
            .bind(id)
            .bind(at.date_naive())
            .execute(&self.pool)
            .await
            .map_err(to_store_error)?;
        Ok(())
    }
}

#[async_trait]
impl HotspotRepository for PostgresStore {
    async fn active_near_route(
        &self,
        route: &Polyline,
        corridor: f64,
        since: DateTime<Utc>,
    ) -> StoreResult<Vec<CountedHotspot>> {
        let sql = format!(
            "SELECT {HOTSPOT_COLUMNS}, \
                (SELECT count(*) FROM votes v WHERE v.hotspot_id = h.id AND v.voted_at >= $3) AS drivers \
             FROM hotspots h \
             WHERE h.status = 'active' AND ST_DWithin(h.location, ST_GeogFromText($1), $2)"
        );
        let rows = sqlx::query(&sql)
            .bind(route_wkt(route))
            .bind(corridor)
            .bind(since)
            .fetch_all(&self.pool)
            .await
            .map_err(to_store_error)?;
        rows.iter().map(counted_from_row).collect()
    }

    async fn near(&self, location: Coordinate, radius: f64) -> StoreResult<Vec<Hotspot>> {
        let sql = format!(
            "SELECT {HOTSPOT_COLUMNS} FROM hotspots h \
             WHERE ST_DWithin(h.location, ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography, $3)"
        );
        let rows = sqlx::query(&sql)
            .bind(location.longitude)
            .bind(location.latitude)
            .bind(radius)
            .fetch_all(&self.pool)
            .await
            .map_err(to_store_error)?;
        rows.iter().map(hotspot_from_row).collect()
    }

    async fn insert(&self, hotspot: &Hotspot) -> StoreResult<()> {
        sqlx::query(
            "INSERT INTO hotspots (id, kind, status, location, bearing, created_at, flagged_for_review, source, \
             reported_crashes) VALUES ($1, $2, $3, ST_SetSRID(ST_MakePoint($4, $5), 4326)::geography, $6, $7, $8, $9, $10)",
        )
        .bind(hotspot.id)
        .bind(kind_code(hotspot.kind))
        .bind(status_code(hotspot.status))
        .bind(hotspot.location.longitude)
        .bind(hotspot.location.latitude)
        .bind(hotspot.bearing.degrees())
        .bind(hotspot.created_at)
        .bind(hotspot.flagged_for_review)
        .bind(source_code(hotspot.source).0)
        .bind(source_code(hotspot.source).1)
        .execute(&self.pool)
        .await
        .map_err(to_store_error)?;
        Ok(())
    }

    async fn record_vote(&self, device: Uuid, hotspot: Uuid, at: DateTime<Utc>) -> StoreResult<()> {
        // One vote per driver: a repeat just moves the time forward.
        sqlx::query(
            "INSERT INTO votes (device_id, hotspot_id, voted_at) VALUES ($1, $2, $3) \
             ON CONFLICT (device_id, hotspot_id) DO UPDATE SET voted_at = GREATEST(votes.voted_at, EXCLUDED.voted_at)",
        )
        .bind(device)
        .bind(hotspot)
        .bind(at)
        .execute(&self.pool)
        .await
        .map_err(to_store_error)?;
        Ok(())
    }

    async fn distinct_drivers(&self, hotspot: Uuid, since: DateTime<Utc>) -> StoreResult<u32> {
        let count: i64 = sqlx::query_scalar("SELECT count(*) FROM votes WHERE hotspot_id = $1 AND voted_at >= $2")
            .bind(hotspot)
            .bind(since)
            .fetch_one(&self.pool)
            .await
            .map_err(to_store_error)?;
        Ok(to_u32(count))
    }

    async fn set_status(&self, hotspot: Uuid, status: HotspotStatus) -> StoreResult<()> {
        sqlx::query("UPDATE hotspots SET status = $2 WHERE id = $1")
            .bind(hotspot)
            .bind(status_code(status))
            .execute(&self.pool)
            .await
            .map_err(to_store_error)?;
        Ok(())
    }

    async fn set_kind(&self, hotspot: Uuid, kind: HotspotKind) -> StoreResult<()> {
        sqlx::query("UPDATE hotspots SET kind = $2 WHERE id = $1")
            .bind(hotspot)
            .bind(kind_code(kind))
            .execute(&self.pool)
            .await
            .map_err(to_store_error)?;
        Ok(())
    }

    async fn record_curve_vote(&self, device: Uuid, hotspot: Uuid, at: DateTime<Utc>) -> StoreResult<()> {
        sqlx::query(
            "INSERT INTO curve_votes (device_id, hotspot_id, voted_at) VALUES ($1, $2, $3) \
             ON CONFLICT (device_id, hotspot_id) DO UPDATE SET voted_at = GREATEST(curve_votes.voted_at, EXCLUDED.voted_at)",
        )
        .bind(device)
        .bind(hotspot)
        .bind(at)
        .execute(&self.pool)
        .await
        .map_err(to_store_error)?;
        Ok(())
    }

    async fn distinct_curve_drivers(&self, hotspot: Uuid, since: DateTime<Utc>) -> StoreResult<u32> {
        let count: i64 =
            sqlx::query_scalar("SELECT count(*) FROM curve_votes WHERE hotspot_id = $1 AND voted_at >= $2")
                .bind(hotspot)
                .bind(since)
                .fetch_one(&self.pool)
                .await
                .map_err(to_store_error)?;
        Ok(to_u32(count))
    }

    async fn active_with_driver_counts(&self, since: DateTime<Utc>) -> StoreResult<Vec<CountedHotspot>> {
        let sql = format!(
            "SELECT {HOTSPOT_COLUMNS}, \
                (SELECT count(*) FROM votes v WHERE v.hotspot_id = h.id AND v.voted_at >= $1) AS drivers \
             FROM hotspots h WHERE h.status = 'active'"
        );
        let rows = sqlx::query(&sql)
            .bind(since)
            .fetch_all(&self.pool)
            .await
            .map_err(to_store_error)?;
        rows.iter().map(counted_from_row).collect()
    }

    async fn flag_for_review(&self, hotspot: Uuid) -> StoreResult<()> {
        sqlx::query("UPDATE hotspots SET flagged_for_review = true WHERE id = $1")
            .bind(hotspot)
            .execute(&self.pool)
            .await
            .map_err(to_store_error)?;
        Ok(())
    }

    async fn replace_city_collision_hotspots(&self, hotspots: &[Hotspot]) -> StoreResult<()> {
        let mut transaction = self.pool.begin().await.map_err(to_store_error)?;
        // Votes on the old ones go with them (ON DELETE CASCADE).
        sqlx::query("DELETE FROM hotspots WHERE source = 'city_collisions'")
            .execute(&mut *transaction)
            .await
            .map_err(to_store_error)?;
        // One statement for the whole set: row-by-row inserts are slow over a hosted database's network.
        let column = |pick: fn(&Hotspot) -> String| hotspots.iter().map(pick).collect::<Vec<_>>();
        sqlx::query(
            "INSERT INTO hotspots (id, kind, status, location, bearing, created_at, flagged_for_review, source, \
             reported_crashes) \
             SELECT id, kind, status, ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography, bearing, \
                    created_at, false, source, reported_crashes \
             FROM UNNEST($1::uuid[], $2::text[], $3::text[], $4::float8[], $5::float8[], $6::float8[], \
                         $7::timestamptz[], $8::text[], $9::int4[]) \
                  AS h(id, kind, status, latitude, longitude, bearing, created_at, source, reported_crashes)",
        )
        .bind(hotspots.iter().map(|h| h.id).collect::<Vec<_>>())
        .bind(column(|h| kind_code(h.kind).to_owned()))
        .bind(column(|h| status_code(h.status).to_owned()))
        .bind(hotspots.iter().map(|h| h.location.latitude).collect::<Vec<_>>())
        .bind(hotspots.iter().map(|h| h.location.longitude).collect::<Vec<_>>())
        .bind(hotspots.iter().map(|h| h.bearing.degrees()).collect::<Vec<_>>())
        .bind(hotspots.iter().map(|h| h.created_at).collect::<Vec<_>>())
        .bind(column(|h| source_code(h.source).0.to_owned()))
        .bind(hotspots.iter().map(|h| source_code(h.source).1).collect::<Vec<_>>())
        .execute(&mut *transaction)
        .await
        .map_err(to_store_error)?;
        transaction.commit().await.map_err(to_store_error)
    }
}

#[async_trait]
impl EventRepository for PostgresStore {
    async fn claim_new(&self, ids: &[Uuid], at: DateTime<Utc>) -> StoreResult<Vec<Uuid>> {
        // ON CONFLICT DO NOTHING + RETURNING gives exactly the ids that weren't there yet, atomically.
        sqlx::query_scalar(
            "INSERT INTO received_ids (id, received_at) SELECT unnest($1::uuid[]), $2 \
             ON CONFLICT (id) DO NOTHING RETURNING id",
        )
        .bind(ids)
        .bind(at)
        .fetch_all(&self.pool)
        .await
        .map_err(to_store_error)
    }

    async fn store_event(&self, device: Uuid, event: &Event) -> StoreResult<()> {
        // Only what the metrics need is kept; hard-brake traces are never stored.
        let (hotspot, outcome, braked_hard, not_helpful) = match &event.kind {
            EventKind::HotspotPassed {
                hotspot_id,
                outcome,
                braked_hard,
            } => (
                Some(*hotspot_id),
                Some(outcome_code(*outcome)),
                Some(*braked_hard),
                None,
            ),
            EventKind::Feedback {
                not_helpful_hotspot,
                helpful,
            } => (*not_helpful_hotspot, None, None, Some(!helpful)),
            _ => (None, None, None, None),
        };
        sqlx::query(
            "INSERT INTO events (id, device_id, hour, kind, hotspot_id, outcome, braked_hard, not_helpful) \
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8) ON CONFLICT (id) DO NOTHING",
        )
        .bind(event.id)
        .bind(device)
        .bind(event.hour)
        .bind(event_code(&event.kind))
        .bind(hotspot)
        .bind(outcome)
        .bind(braked_hard)
        .bind(not_helpful)
        .execute(&self.pool)
        .await
        .map_err(to_store_error)?;
        Ok(())
    }

    async fn store_counters(&self, device: Uuid, counters: &UsageCounters) -> StoreResult<()> {
        let as_int = |value: u32| i32::try_from(value).unwrap_or(i32::MAX);
        sqlx::query(
            "INSERT INTO usage_counters (id, device_id, hour, warnings_shown, warnings_suppressed, mutes, hotspots_passed) \
             VALUES ($1, $2, $3, $4, $5, $6, $7) ON CONFLICT (id) DO NOTHING",
        )
        .bind(counters.id)
        .bind(device)
        .bind(counters.hour)
        .bind(as_int(counters.warnings_shown))
        .bind(as_int(counters.warnings_suppressed))
        .bind(as_int(counters.mutes))
        .bind(as_int(counters.hotspots_passed))
        .execute(&self.pool)
        .await
        .map_err(to_store_error)?;
        Ok(())
    }

    async fn feedback_counts(&self, hotspot: Uuid) -> StoreResult<(u32, u32)> {
        let row = sqlx::query(
            "SELECT \
                count(*) FILTER (WHERE kind = 'hotspot_passed' AND outcome = 'warned') AS warned, \
                count(*) FILTER (WHERE kind = 'feedback' AND not_helpful) AS not_helpful \
             FROM events WHERE hotspot_id = $1",
        )
        .bind(hotspot)
        .fetch_one(&self.pool)
        .await
        .map_err(to_store_error)?;
        let warned: i64 = row.try_get("warned").map_err(to_store_error)?;
        let not_helpful: i64 = row.try_get("not_helpful").map_err(to_store_error)?;
        Ok((to_u32(warned), to_u32(not_helpful)))
    }

    async fn pass_counts(&self, since: DateTime<Utc>) -> StoreResult<PassCounts> {
        let row = sqlx::query(
            "SELECT \
                count(*) FILTER (WHERE outcome = 'warned') AS warned, \
                count(*) FILTER (WHERE outcome = 'warned' AND braked_hard) AS warned_braked, \
                count(*) FILTER (WHERE outcome <> 'warned') AS unwarned, \
                count(*) FILTER (WHERE outcome <> 'warned' AND braked_hard) AS unwarned_braked \
             FROM events WHERE kind = 'hotspot_passed' AND hour >= $1",
        )
        .bind(since)
        .fetch_one(&self.pool)
        .await
        .map_err(to_store_error)?;
        let get = |column: &str| row.try_get::<i64, _>(column).map(to_u32).map_err(to_store_error);
        Ok(PassCounts {
            warned: get("warned")?,
            warned_with_hard_brake: get("warned_braked")?,
            unwarned: get("unwarned")?,
            unwarned_with_hard_brake: get("unwarned_braked")?,
        })
    }

    async fn mute_counts(&self, since: DateTime<Utc>) -> StoreResult<(u32, u32)> {
        let row = sqlx::query(
            "SELECT \
                (SELECT count(DISTINCT device_id) FROM device_activity WHERE day >= $1::date) AS active, \
                (SELECT count(DISTINCT device_id) FROM ( \
                    SELECT device_id FROM events WHERE kind = 'muted' AND hour >= $1 \
                    UNION SELECT device_id FROM usage_counters WHERE mutes > 0 AND hour >= $1) muted) AS muted",
        )
        .bind(since)
        .fetch_one(&self.pool)
        .await
        .map_err(to_store_error)?;
        let active: i64 = row.try_get("active").map_err(to_store_error)?;
        let muted: i64 = row.try_get("muted").map_err(to_store_error)?;
        Ok((to_u32(active), to_u32(muted)))
    }

    async fn week_one_retention_counts(&self, now: DateTime<Utc>) -> StoreResult<(u32, u32)> {
        let row = sqlx::query(
            "SELECT count(*) AS new_devices, count(*) FILTER (WHERE last_day >= first_day + 7) AS retained \
             FROM (SELECT min(day) AS first_day, max(day) AS last_day FROM device_activity GROUP BY device_id) d \
             WHERE first_day <= $1::date",
        )
        .bind((now - Duration::days(7)).date_naive())
        .fetch_one(&self.pool)
        .await
        .map_err(to_store_error)?;
        let new_devices: i64 = row.try_get("new_devices").map_err(to_store_error)?;
        let retained: i64 = row.try_get("retained").map_err(to_store_error)?;
        Ok((to_u32(new_devices), to_u32(retained)))
    }
}

/// Where the app's tables live. Not `public`, which hosted Postgres (Supabase) exposes through its Data API.
const APP_SCHEMA: &str = "roadsense";

/// Creates a fresh schema and a pool that uses it, so integration tests don't touch each other's data.
pub async fn isolated_pool(url: &str, schema: &str) -> StoreResult<PgPool> {
    pool_in_schema(url, schema, 5).await
}

/// A pool whose connections create and use tables in `schema`, creating the schema first if needed.
async fn pool_in_schema(url: &str, schema: &str, max_connections: u32) -> StoreResult<PgPool> {
    let admin = PgPoolOptions::new()
        .max_connections(1)
        .connect(url)
        .await
        .map_err(to_store_error)?;
    admin
        .execute(format!("CREATE SCHEMA IF NOT EXISTS {schema}").as_str())
        .await
        .map_err(to_store_error)?;
    admin.close().await;
    // PostGIS is in `extensions` on Supabase and in `public` locally; keep both on the path (missing ones are skipped).
    let search_path = format!("SET search_path TO {schema}, extensions, public");
    PgPoolOptions::new()
        .max_connections(max_connections)
        .after_connect(move |connection, _| {
            let search_path = search_path.clone();
            Box::pin(async move {
                connection.execute(search_path.as_str()).await?;
                Ok(())
            })
        })
        .connect(url)
        .await
        .map_err(to_store_error)
}
