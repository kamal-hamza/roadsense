//! The use cases the handlers call, built once by the composition root (main.rs).

use std::sync::Arc;

use roadsense_application::ports::HealthCheck;

use roadsense_application::use_cases::{
    AcceptUpload, ComputeMetrics, DemoteStaleHotspots, LookupRouteHotspots, ProcessEvents, RegisterDevice,
};

/// Shared by every request. Cheap to clone (everything is behind an Arc).
#[derive(Clone)]
pub struct AppState {
    pub register_device: Arc<RegisterDevice>,
    pub lookup_route_hotspots: Arc<LookupRouteHotspots>,
    pub accept_upload: Arc<AcceptUpload>,
    pub process_events: Arc<ProcessEvents>,
    pub compute_metrics: Arc<ComputeMetrics>,
    pub demote_stale_hotspots: Arc<DemoteStaleHotspots>,
    pub health: Arc<dyn HealthCheck>,
    /// Secret for the internal endpoints (metrics, demotion). `None` turns them off.
    pub admin_token: Option<Arc<str>>,
}
