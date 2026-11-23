use std::sync::Arc;

use roadsense_domain::geo::{Coordinate, Polyline};
use roadsense_domain::hotspot::RouteHotspot;
use roadsense_domain::lookup::RouteLookup;
use thiserror::Error;
use uuid::Uuid;

use crate::ports::{Clock, DeviceRepository, HotspotRepository, StoreError};

#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum LookupError {
    #[error("unknown device")]
    UnknownDevice,
    #[error("the route needs at least two distinct, valid points")]
    InvalidRoute,
    #[error(transparent)]
    Store(#[from] StoreError),
}

/// Hotspots on a route, going the driver's way (activity diagram 2). The route itself is never stored.
pub struct LookupRouteHotspots {
    pub devices: Arc<dyn DeviceRepository>,
    pub hotspots: Arc<dyn HotspotRepository>,
    pub lookup: RouteLookup,
    pub clock: Arc<dyn Clock>,
}

impl LookupRouteHotspots {
    pub async fn execute(&self, device: Uuid, points: Vec<Coordinate>) -> Result<Vec<RouteHotspot>, LookupError> {
        if !self.devices.exists(device).await? {
            return Err(LookupError::UnknownDevice);
        }
        let route = Polyline::new(points).ok_or(LookupError::InvalidRoute)?;
        let since = self.lookup.consensus.window_start(self.clock.now());
        // Storage narrows it to the corridor; the domain applies direction, consensus, and merging.
        let candidates = self
            .hotspots
            .active_near_route(&route, self.lookup.matching.radius, since)
            .await?;
        Ok(self.lookup.select(&route, candidates))
    }
}
