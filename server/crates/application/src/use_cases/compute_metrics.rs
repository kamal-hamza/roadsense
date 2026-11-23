use std::sync::Arc;

use chrono::Duration;
use roadsense_domain::metrics::{SuccessMetrics, rate};

use crate::ports::{Clock, EventRepository, StoreResult};

/// The three success metrics, over the last 90 days (week-one retention looks at every device).
pub struct ComputeMetrics {
    pub events: Arc<dyn EventRepository>,
    pub clock: Arc<dyn Clock>,
}

impl ComputeMetrics {
    pub async fn execute(&self) -> StoreResult<SuccessMetrics> {
        let now = self.clock.now();
        let since = now - Duration::days(90);
        let passes = self.events.pass_counts(since).await?;
        let (active, muted) = self.events.mute_counts(since).await?;
        let (new_devices, retained) = self.events.week_one_retention_counts(now).await?;
        Ok(SuccessMetrics {
            passes,
            mute_rate: rate(muted, active),
            week_one_retention: rate(retained, new_devices),
        })
    }
}
