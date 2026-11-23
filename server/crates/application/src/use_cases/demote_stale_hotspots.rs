use std::sync::Arc;

use roadsense_domain::hotspot::HotspotStatus;
use roadsense_domain::rules::Consensus;

use crate::ports::{Clock, HotspotRepository, StoreResult};

/// Nightly: active hotspots whose 12-month driver count fell below the consensus go back to candidate.
pub struct DemoteStaleHotspots {
    pub hotspots: Arc<dyn HotspotRepository>,
    pub consensus: Consensus,
    pub clock: Arc<dyn Clock>,
}

impl DemoteStaleHotspots {
    /// Returns how many hotspots were demoted.
    pub async fn execute(&self) -> StoreResult<u32> {
        let since = self.consensus.window_start(self.clock.now());
        let mut demoted = 0;
        for counted in self.hotspots.active_with_driver_counts(since).await? {
            // Old votes age out, so a fixed road stops producing warnings.
            if !self.consensus.is_met(counted.driver_count) {
                self.hotspots
                    .set_status(counted.hotspot.id, HotspotStatus::Candidate)
                    .await?;
                demoted += 1;
            }
        }
        Ok(demoted)
    }
}
