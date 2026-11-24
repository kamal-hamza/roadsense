//! Wires storage into the use cases. Used by main.rs and by the API tests (with the in-memory store).

use std::sync::Arc;

use async_trait::async_trait;
use roadsense_application::ports::{
    Clock, DeviceRepository, EventRepository, HealthCheck, HotspotRepository, RoadNetwork, StoreResult, SystemClock,
};
use roadsense_application::use_cases::{
    AcceptUpload, ComputeMetrics, DemoteStaleHotspots, LookupRouteHotspots, ProcessEvents, RegisterDevice,
};
use roadsense_domain::classify::{Classifier, RoadWay};
use roadsense_domain::events::Plausibility;
use roadsense_domain::geo::Coordinate;
use roadsense_domain::lookup::RouteLookup;
use roadsense_domain::rules::{Consensus, FeedbackReview, HotspotMatch};
use roadsense_infrastructure::memory::MemoryStore;
use roadsense_infrastructure::rate_limiter::FixedWindowRateLimiter;

use crate::state::AppState;

/// The storage behind every port, chosen once at startup.
pub struct Storage {
    pub devices: Arc<dyn DeviceRepository>,
    pub hotspots: Arc<dyn HotspotRepository>,
    pub events: Arc<dyn EventRepository>,
    pub roads: Arc<dyn RoadNetwork>,
    pub health: Arc<dyn HealthCheck>,
}

impl Storage {
    /// Everything in memory, with no map data. For demos without a database, and for tests.
    pub fn in_memory() -> Self {
        let memory = Arc::new(MemoryStore::default());
        Self {
            devices: memory.clone(),
            hotspots: memory.clone(),
            events: memory.clone(),
            roads: Arc::new(NoRoads),
            health: memory,
        }
    }
}

/// No map data: every new hotspot is classified as sudden stops.
pub struct NoRoads;

#[async_trait]
impl RoadNetwork for NoRoads {
    async fn ways_near(&self, _location: Coordinate, _radius: f64) -> StoreResult<Vec<RoadWay>> {
        Ok(Vec::new())
    }
}

/// Builds every use case with the default rules and the real clock. `admin_token` guards the internal endpoints.
pub fn build_state(storage: Storage, admin_token: Option<String>) -> AppState {
    let clock: Arc<dyn Clock> = Arc::new(SystemClock);
    let consensus = Consensus::default();
    AppState {
        register_device: Arc::new(RegisterDevice {
            devices: storage.devices.clone(),
            clock: clock.clone(),
        }),
        lookup_route_hotspots: Arc::new(LookupRouteHotspots {
            devices: storage.devices.clone(),
            hotspots: storage.hotspots.clone(),
            lookup: RouteLookup::default(),
            clock: clock.clone(),
        }),
        accept_upload: Arc::new(AcceptUpload {
            devices: storage.devices.clone(),
            events: storage.events.clone(),
            rate_limiter: Arc::new(FixedWindowRateLimiter::default()),
            clock: clock.clone(),
        }),
        process_events: Arc::new(ProcessEvents {
            hotspots: storage.hotspots.clone(),
            events: storage.events.clone(),
            roads: storage.roads,
            clock: clock.clone(),
            plausibility: Plausibility::default(),
            matching: HotspotMatch::default(),
            consensus,
            classifier: Classifier::default(),
            review: FeedbackReview::default(),
        }),
        compute_metrics: Arc::new(ComputeMetrics {
            events: storage.events,
            clock: clock.clone(),
        }),
        demote_stale_hotspots: Arc::new(DemoteStaleHotspots {
            hotspots: storage.hotspots,
            consensus,
            clock,
        }),
        health: storage.health,
        admin_token: admin_token.filter(|token| !token.is_empty()).map(Into::into),
    }
}
