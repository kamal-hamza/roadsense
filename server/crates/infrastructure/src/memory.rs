//! An in-memory store for running the API without a database (local demos) and for API tests.

use std::collections::{HashMap, HashSet};
use std::sync::{Mutex, MutexGuard};

use async_trait::async_trait;
use chrono::{DateTime, Duration, NaiveDate, Utc};
use roadsense_application::ports::{DeviceRepository, EventRepository, HealthCheck, HotspotRepository, StoreResult};
use roadsense_domain::events::{Event, EventKind, PassOutcome, UsageCounters};
use roadsense_domain::geo::{Coordinate, Polyline};
use roadsense_domain::hotspot::{CountedHotspot, Hotspot, HotspotStatus};
use roadsense_domain::metrics::PassCounts;
use uuid::Uuid;

#[derive(Default)]
struct State {
    devices: HashSet<Uuid>,
    activity: HashMap<Uuid, HashSet<NaiveDate>>,
    hotspots: Vec<Hotspot>,
    votes: HashMap<(Uuid, Uuid), DateTime<Utc>>,
    received: HashSet<Uuid>,
    events: Vec<(Uuid, Event)>,
    counters: Vec<(Uuid, UsageCounters)>,
}

impl State {
    fn drivers(&self, hotspot: Uuid, since: DateTime<Utc>) -> u32 {
        let count = self
            .votes
            .iter()
            .filter(|((_, id), at)| *id == hotspot && **at >= since)
            .count();
        u32::try_from(count).unwrap_or(u32::MAX)
    }

    fn counted(&self, hotspot: &Hotspot, since: DateTime<Utc>) -> CountedHotspot {
        CountedHotspot {
            hotspot: hotspot.clone(),
            driver_count: self.drivers(hotspot.id, since),
        }
    }
}

/// Everything in one mutex-protected struct; fine for demos and tests, not for production load.
#[derive(Default)]
pub struct MemoryStore {
    state: Mutex<State>,
}

impl MemoryStore {
    fn state(&self) -> MutexGuard<'_, State> {
        // A poisoned lock only means a request panicked mid-update; the data is still usable for a demo.
        self.state.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    /// All hotspots, for tests and the demo seed.
    pub fn hotspots(&self) -> Vec<Hotspot> {
        self.state().hotspots.clone()
    }
}

#[async_trait]
impl DeviceRepository for MemoryStore {
    async fn register(&self, id: Uuid, _at: DateTime<Utc>) -> StoreResult<()> {
        self.state().devices.insert(id);
        Ok(())
    }

    async fn exists(&self, id: Uuid) -> StoreResult<bool> {
        Ok(self.state().devices.contains(&id))
    }

    async fn record_activity(&self, id: Uuid, at: DateTime<Utc>) -> StoreResult<()> {
        self.state().activity.entry(id).or_default().insert(at.date_naive());
        Ok(())
    }
}

#[async_trait]
impl HotspotRepository for MemoryStore {
    async fn active_near_route(
        &self,
        route: &Polyline,
        corridor: f64,
        since: DateTime<Utc>,
    ) -> StoreResult<Vec<CountedHotspot>> {
        let state = self.state();
        Ok(state
            .hotspots
            .iter()
            .filter(|h| h.status == HotspotStatus::Active && route.project(&h.location).distance_away <= corridor)
            .map(|h| state.counted(h, since))
            .collect())
    }

    async fn near(&self, location: Coordinate, radius: f64) -> StoreResult<Vec<Hotspot>> {
        Ok(self
            .state()
            .hotspots
            .iter()
            .filter(|h| h.location.distance_to(&location) <= radius)
            .cloned()
            .collect())
    }

    async fn insert(&self, hotspot: &Hotspot) -> StoreResult<()> {
        self.state().hotspots.push(hotspot.clone());
        Ok(())
    }

    async fn record_vote(&self, device: Uuid, hotspot: Uuid, at: DateTime<Utc>) -> StoreResult<()> {
        self.state().votes.insert((device, hotspot), at);
        Ok(())
    }

    async fn distinct_drivers(&self, hotspot: Uuid, since: DateTime<Utc>) -> StoreResult<u32> {
        Ok(self.state().drivers(hotspot, since))
    }

    async fn set_status(&self, hotspot: Uuid, status: HotspotStatus) -> StoreResult<()> {
        self.state()
            .hotspots
            .iter_mut()
            .filter(|h| h.id == hotspot)
            .for_each(|h| h.status = status);
        Ok(())
    }

    async fn active_with_driver_counts(&self, since: DateTime<Utc>) -> StoreResult<Vec<CountedHotspot>> {
        let state = self.state();
        Ok(state
            .hotspots
            .iter()
            .filter(|h| h.status == HotspotStatus::Active)
            .map(|h| state.counted(h, since))
            .collect())
    }

    async fn flag_for_review(&self, hotspot: Uuid) -> StoreResult<()> {
        self.state()
            .hotspots
            .iter_mut()
            .filter(|h| h.id == hotspot)
            .for_each(|h| h.flagged_for_review = true);
        Ok(())
    }
}

#[async_trait]
impl EventRepository for MemoryStore {
    async fn claim_new(&self, ids: &[Uuid], _at: DateTime<Utc>) -> StoreResult<Vec<Uuid>> {
        let mut state = self.state();
        Ok(ids.iter().copied().filter(|id| state.received.insert(*id)).collect())
    }

    async fn store_event(&self, device: Uuid, event: &Event) -> StoreResult<()> {
        self.state().events.push((device, event.clone()));
        Ok(())
    }

    async fn store_counters(&self, device: Uuid, counters: &UsageCounters) -> StoreResult<()> {
        self.state().counters.push((device, *counters));
        Ok(())
    }

    async fn feedback_counts(&self, hotspot: Uuid) -> StoreResult<(u32, u32)> {
        let state = self.state();
        let warned = state.events.iter().filter(|(_, event)| {
            matches!(&event.kind, EventKind::HotspotPassed { hotspot_id, outcome: PassOutcome::Warned { .. }, .. }
                if *hotspot_id == hotspot)
        });
        let not_helpful = state.events.iter().filter(|(_, event)| {
            matches!(&event.kind, EventKind::Feedback { not_helpful_hotspot: Some(id), .. } if *id == hotspot)
        });
        Ok((count(warned), count(not_helpful)))
    }

    async fn pass_counts(&self, since: DateTime<Utc>) -> StoreResult<PassCounts> {
        let mut counts = PassCounts::default();
        for (_, event) in self.state().events.iter().filter(|(_, event)| event.hour >= since) {
            if let EventKind::HotspotPassed {
                outcome, braked_hard, ..
            } = &event.kind
            {
                let (passes, braked) = if outcome.was_warned() {
                    (&mut counts.warned, &mut counts.warned_with_hard_brake)
                } else {
                    (&mut counts.unwarned, &mut counts.unwarned_with_hard_brake)
                };
                *passes += 1;
                *braked += u32::from(*braked_hard);
            }
        }
        Ok(counts)
    }

    async fn mute_counts(&self, since: DateTime<Utc>) -> StoreResult<(u32, u32)> {
        let state = self.state();
        let since_day = since.date_naive();
        let active = state
            .activity
            .values()
            .filter(|days| days.iter().any(|day| *day >= since_day));
        let mut muted: HashSet<Uuid> = state
            .events
            .iter()
            .filter(|(_, event)| event.hour >= since && event.kind == EventKind::Muted)
            .map(|(device, _)| *device)
            .collect();
        muted.extend(
            state
                .counters
                .iter()
                .filter(|(_, c)| c.hour >= since && c.mutes > 0)
                .map(|(device, _)| *device),
        );
        Ok((count(active), u32::try_from(muted.len()).unwrap_or(u32::MAX)))
    }

    async fn week_one_retention_counts(&self, now: DateTime<Utc>) -> StoreResult<(u32, u32)> {
        let state = self.state();
        let cutoff = (now - Duration::days(7)).date_naive();
        let mut new_devices = 0;
        let mut retained = 0;
        for days in state.activity.values() {
            let (Some(first), Some(last)) = (days.iter().min(), days.iter().max()) else {
                continue;
            };
            // Only devices that have had a full week since their first trip can count.
            if *first <= cutoff {
                new_devices += 1;
                retained += u32::from(*last >= *first + Duration::days(7));
            }
        }
        Ok((new_devices, retained))
    }
}

#[async_trait]
impl HealthCheck for MemoryStore {
    async fn check(&self) -> StoreResult<()> {
        Ok(())
    }
}

fn count<T>(items: impl Iterator<Item = T>) -> u32 {
    u32::try_from(items.count()).unwrap_or(u32::MAX)
}
