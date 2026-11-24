//! Ports: what the use cases need from storage, maps, and the clock. Implemented in infrastructure.

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use roadsense_domain::classify::RoadWay;
use roadsense_domain::events::{Event, UsageCounters};
use roadsense_domain::geo::{Coordinate, Polyline};
use roadsense_domain::hotspot::{CountedHotspot, Hotspot, HotspotStatus};
use roadsense_domain::metrics::PassCounts;
use thiserror::Error;
use uuid::Uuid;

/// Storage failed. Infrastructure maps database errors to this so they don't leak through the ports.
#[derive(Debug, Clone, PartialEq, Eq, Error)]
#[error("storage unavailable: {0}")]
pub struct StoreError(pub String);

pub type StoreResult<T> = Result<T, StoreError>;

/// Anonymous devices that may use the API.
#[async_trait]
pub trait DeviceRepository: Send + Sync {
    /// Registers `id`; registering again is fine.
    async fn register(&self, id: Uuid, at: DateTime<Utc>) -> StoreResult<()>;
    async fn exists(&self, id: Uuid) -> StoreResult<bool>;
    /// Notes that the device uploaded on this day (for week-one retention).
    async fn record_activity(&self, id: Uuid, at: DateTime<Utc>) -> StoreResult<()>;
}

/// Hotspots and the votes behind them.
#[async_trait]
pub trait HotspotRepository: Send + Sync {
    /// Active hotspots within `corridor` meters of `route`, with distinct drivers since `since`.
    async fn active_near_route(
        &self,
        route: &Polyline,
        corridor: f64,
        since: DateTime<Utc>,
    ) -> StoreResult<Vec<CountedHotspot>>;
    /// Every hotspot (any status) within `radius` meters of `location`.
    async fn near(&self, location: Coordinate, radius: f64) -> StoreResult<Vec<Hotspot>>;
    async fn insert(&self, hotspot: &Hotspot) -> StoreResult<()>;
    /// One vote per device per hotspot: a repeat only moves the vote's time.
    async fn record_vote(&self, device: Uuid, hotspot: Uuid, at: DateTime<Utc>) -> StoreResult<()>;
    async fn distinct_drivers(&self, hotspot: Uuid, since: DateTime<Utc>) -> StoreResult<u32>;
    async fn set_status(&self, hotspot: Uuid, status: HotspotStatus) -> StoreResult<()>;
    /// Every active hotspot with its distinct drivers since `since` (for the nightly job).
    async fn active_with_driver_counts(&self, since: DateTime<Utc>) -> StoreResult<Vec<CountedHotspot>>;
    async fn flag_for_review(&self, hotspot: Uuid) -> StoreResult<()>;
    /// Deletes every hotspot from the city's collision records (with their votes) and inserts `hotspots`, as
    /// one change.
    async fn replace_city_collision_hotspots(&self, hotspots: &[Hotspot]) -> StoreResult<()>;
}

/// Uploaded events, kept for de-duplication and the success metrics.
#[async_trait]
pub trait EventRepository: Send + Sync {
    /// Records event ids as received and returns the ones never seen before.
    async fn claim_new(&self, ids: &[Uuid], at: DateTime<Utc>) -> StoreResult<Vec<Uuid>>;
    async fn store_event(&self, device: Uuid, event: &Event) -> StoreResult<()>;
    async fn store_counters(&self, device: Uuid, counters: &UsageCounters) -> StoreResult<()>;
    /// Warned passes and "not helpful" replies for a hotspot.
    async fn feedback_counts(&self, hotspot: Uuid) -> StoreResult<(u32, u32)>;
    async fn pass_counts(&self, since: DateTime<Utc>) -> StoreResult<PassCounts>;
    /// Devices active since `since`, and how many of them muted at least once.
    async fn mute_counts(&self, since: DateTime<Utc>) -> StoreResult<(u32, u32)>;
    /// Devices first seen at least 7 days before `now`, and how many were active 7+ days after that.
    async fn week_one_retention_counts(&self, now: DateTime<Utc>) -> StoreResult<(u32, u32)>;
}

/// Whether storage is reachable, for the health check (a keep-alive ping also keeps a free database awake).
#[async_trait]
pub trait HealthCheck: Send + Sync {
    async fn check(&self) -> StoreResult<()>;
}

/// Road geometry from the map, for classifying hotspots.
#[async_trait]
pub trait RoadNetwork: Send + Sync {
    /// Roads within `radius` meters of `location`. Empty when there's no map data there.
    async fn ways_near(&self, location: Coordinate, radius: f64) -> StoreResult<Vec<RoadWay>>;
}

/// Limits how often one device can upload.
pub trait RateLimiter: Send + Sync {
    /// Whether `device` may upload now; counts the attempt if so.
    fn allow(&self, device: Uuid, now: DateTime<Utc>) -> bool;
}

/// The current time, injected so tests are deterministic.
pub trait Clock: Send + Sync {
    fn now(&self) -> DateTime<Utc>;
}

/// The real clock.
pub struct SystemClock;

impl Clock for SystemClock {
    fn now(&self) -> DateTime<Utc> {
        Utc::now()
    }
}
