//! A simple per-device upload limit.

use std::collections::HashMap;
use std::sync::Mutex;

use chrono::{DateTime, Duration, Utc};
use roadsense_application::ports::RateLimiter;
use uuid::Uuid;

/// Allows `limit` uploads per device per `window` (fixed windows), in memory.
pub struct FixedWindowRateLimiter {
    limit: u32,
    window: Duration,
    // Device -> (window start, uploads so far). A Mutex is enough: it's held for a hash lookup only.
    counts: Mutex<HashMap<Uuid, (DateTime<Utc>, u32)>>,
}

impl FixedWindowRateLimiter {
    pub fn new(limit: u32, window: Duration) -> Self {
        Self {
            limit,
            window,
            counts: Mutex::new(HashMap::new()),
        }
    }
}

impl Default for FixedWindowRateLimiter {
    /// 30 uploads an hour: far more than a phone sends after normal drives.
    fn default() -> Self {
        Self::new(30, Duration::hours(1))
    }
}

impl RateLimiter for FixedWindowRateLimiter {
    fn allow(&self, device: Uuid, now: DateTime<Utc>) -> bool {
        // A poisoned lock only means another request panicked mid-update; the counts are still usable.
        let mut counts = self.counts.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        let entry = counts.entry(device).or_insert((now, 0));
        if now - entry.0 >= self.window {
            *entry = (now, 0);
        }
        if entry.1 >= self.limit {
            return false;
        }
        entry.1 += 1;
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn allows_up_to_the_limit_per_window() {
        let limiter = FixedWindowRateLimiter::new(2, Duration::hours(1));
        let device = Uuid::new_v4();
        let now = Utc::now();
        assert!(limiter.allow(device, now));
        assert!(limiter.allow(device, now));
        assert!(!limiter.allow(device, now));
        assert!(limiter.allow(Uuid::new_v4(), now), "limits are per device");
        assert!(
            limiter.allow(device, now + Duration::hours(1)),
            "a new window starts fresh"
        );
    }
}
