//! One use case per operation, each holding the ports it needs.

mod accept_upload;
mod compute_metrics;
mod demote_stale_hotspots;
mod lookup_route_hotspots;
mod process_events;
mod register_device;

pub use accept_upload::{AcceptUpload, Upload, UploadError, UploadOutcome};
pub use compute_metrics::ComputeMetrics;
pub use demote_stale_hotspots::DemoteStaleHotspots;
pub use lookup_route_hotspots::{LookupError, LookupRouteHotspots};
pub use process_events::{ProcessEvents, ProcessReport};
pub use register_device::RegisterDevice;
