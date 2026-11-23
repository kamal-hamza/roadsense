use std::sync::Arc;

use roadsense_domain::events::{Event, UsageCounters};
use thiserror::Error;
use uuid::Uuid;

use crate::ports::{Clock, DeviceRepository, EventRepository, RateLimiter, StoreError};

/// What the app sent: events, or only counts when data sharing is off.
#[derive(Debug, Clone, PartialEq)]
pub enum Upload {
    Events(Vec<Event>),
    Counters(UsageCounters),
}

/// The reply the app gets right away; event processing happens after it.
#[derive(Debug, Clone, PartialEq)]
pub enum UploadOutcome {
    /// New events to process in the background (may be empty for counters).
    Accepted(Vec<Event>),
    /// Every event was received before; nothing to do.
    AlreadyReceived,
}

#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum UploadError {
    #[error("unknown device")]
    UnknownDevice,
    #[error("too many uploads from this device; try again later")]
    RateLimited,
    #[error(transparent)]
    Store(#[from] StoreError),
}

/// The checks before replying to an upload (activity diagram 7, top): device, duplicates, rate limit.
pub struct AcceptUpload {
    pub devices: Arc<dyn DeviceRepository>,
    pub events: Arc<dyn EventRepository>,
    pub rate_limiter: Arc<dyn RateLimiter>,
    pub clock: Arc<dyn Clock>,
}

impl AcceptUpload {
    pub async fn execute(&self, device: Uuid, upload: Upload) -> Result<UploadOutcome, UploadError> {
        let now = self.clock.now();
        if !self.devices.exists(device).await? {
            return Err(UploadError::UnknownDevice);
        }
        // Duplicates are checked before the rate limit, so a retry of something already received never gets a 429.
        let ids: Vec<Uuid> = match &upload {
            Upload::Events(events) => events.iter().map(|event| event.id).collect(),
            Upload::Counters(counters) => vec![counters.id],
        };
        if !ids.is_empty() && self.events.claim_new(&ids, now).await?.is_empty() {
            return Ok(UploadOutcome::AlreadyReceived);
        }
        if !self.rate_limiter.allow(device, now) {
            return Err(UploadError::RateLimited);
        }
        self.devices.record_activity(device, now).await?;
        match upload {
            Upload::Counters(counters) => {
                self.events.store_counters(device, &counters).await?;
                Ok(UploadOutcome::Accepted(Vec::new()))
            }
            Upload::Events(events) => Ok(UploadOutcome::Accepted(events)),
        }
    }
}
