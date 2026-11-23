use std::sync::Arc;

use uuid::Uuid;

use crate::ports::{Clock, DeviceRepository, StoreResult};

/// Registers an app install's anonymous device id.
pub struct RegisterDevice {
    pub devices: Arc<dyn DeviceRepository>,
    pub clock: Arc<dyn Clock>,
}

impl RegisterDevice {
    pub async fn execute(&self, device: Uuid) -> StoreResult<()> {
        self.devices.register(device, self.clock.now()).await
    }
}
