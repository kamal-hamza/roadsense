//! Use-case tests against in-memory fakes of the ports.

use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use chrono::{DateTime, Duration, Utc};
use roadsense_application::ports::*;
use roadsense_application::use_cases::*;
use roadsense_domain::classify::{Classifier, RoadWay};
use roadsense_domain::events::{Event, EventKind, HardBrake, Plausibility, TracePoint, UsageCounters};
use roadsense_domain::geo::{Bearing, Coordinate, Polyline};
use roadsense_domain::hotspot::{CountedHotspot, Hotspot, HotspotKind, HotspotStatus};
use roadsense_domain::lookup::RouteLookup;
use roadsense_domain::metrics::PassCounts;
use roadsense_domain::rules::{Consensus, FeedbackReview, HotspotMatch};
use uuid::Uuid;

const ORIGIN: Coordinate = Coordinate {
    latitude: 47.6,
    longitude: -122.3,
};

fn now() -> DateTime<Utc> {
    DateTime::from_timestamp(1_800_000_000, 0).expect("valid time")
}

fn north(meters: f64) -> Coordinate {
    ORIGIN.offset(meters, Bearing::new(0.0))
}

// --- Fakes ---

struct FixedClock(DateTime<Utc>);
impl Clock for FixedClock {
    fn now(&self) -> DateTime<Utc> {
        self.0
    }
}

#[derive(Default)]
struct Devices(Mutex<HashSet<Uuid>>, Mutex<Vec<Uuid>>);
#[async_trait]
impl DeviceRepository for Devices {
    async fn register(&self, id: Uuid, _: DateTime<Utc>) -> StoreResult<()> {
        self.0.lock().unwrap().insert(id);
        Ok(())
    }
    async fn exists(&self, id: Uuid) -> StoreResult<bool> {
        Ok(self.0.lock().unwrap().contains(&id))
    }
    async fn record_activity(&self, id: Uuid, _: DateTime<Utc>) -> StoreResult<()> {
        self.1.lock().unwrap().push(id);
        Ok(())
    }
}

#[derive(Default)]
struct Hotspots {
    hotspots: Mutex<Vec<Hotspot>>,
    votes: Mutex<HashMap<(Uuid, Uuid), DateTime<Utc>>>,
}
impl Hotspots {
    fn all(&self) -> Vec<Hotspot> {
        self.hotspots.lock().unwrap().clone()
    }
    fn drivers(&self, hotspot: Uuid, since: DateTime<Utc>) -> u32 {
        self.votes
            .lock()
            .unwrap()
            .iter()
            .filter(|((_, h), at)| *h == hotspot && **at >= since)
            .count() as u32
    }
}
#[async_trait]
impl HotspotRepository for Hotspots {
    async fn active_near_route(
        &self,
        route: &Polyline,
        corridor: f64,
        since: DateTime<Utc>,
    ) -> StoreResult<Vec<CountedHotspot>> {
        Ok(self
            .all()
            .into_iter()
            .filter(|h| h.status == HotspotStatus::Active && route.project(&h.location).distance_away <= corridor)
            .map(|h| CountedHotspot {
                driver_count: self.drivers(h.id, since),
                hotspot: h,
            })
            .collect())
    }
    async fn near(&self, location: Coordinate, radius: f64) -> StoreResult<Vec<Hotspot>> {
        Ok(self
            .all()
            .into_iter()
            .filter(|h| h.location.distance_to(&location) <= radius)
            .collect())
    }
    async fn insert(&self, hotspot: &Hotspot) -> StoreResult<()> {
        self.hotspots.lock().unwrap().push(hotspot.clone());
        Ok(())
    }
    async fn record_vote(&self, device: Uuid, hotspot: Uuid, at: DateTime<Utc>) -> StoreResult<()> {
        self.votes.lock().unwrap().insert((device, hotspot), at);
        Ok(())
    }
    async fn distinct_drivers(&self, hotspot: Uuid, since: DateTime<Utc>) -> StoreResult<u32> {
        Ok(self.drivers(hotspot, since))
    }
    async fn set_status(&self, hotspot: Uuid, status: HotspotStatus) -> StoreResult<()> {
        self.hotspots
            .lock()
            .unwrap()
            .iter_mut()
            .filter(|h| h.id == hotspot)
            .for_each(|h| h.status = status);
        Ok(())
    }
    async fn active_with_driver_counts(&self, since: DateTime<Utc>) -> StoreResult<Vec<CountedHotspot>> {
        Ok(self
            .all()
            .into_iter()
            .filter(|h| h.status == HotspotStatus::Active)
            .map(|h| CountedHotspot {
                driver_count: self.drivers(h.id, since),
                hotspot: h,
            })
            .collect())
    }
    async fn flag_for_review(&self, hotspot: Uuid) -> StoreResult<()> {
        self.hotspots
            .lock()
            .unwrap()
            .iter_mut()
            .filter(|h| h.id == hotspot)
            .for_each(|h| h.flagged_for_review = true);
        Ok(())
    }
}

#[derive(Default)]
struct Events {
    seen: Mutex<HashSet<Uuid>>,
    stored: Mutex<Vec<(Uuid, Event)>>,
    counters: Mutex<Vec<UsageCounters>>,
    feedback: Mutex<(u32, u32)>,
}
#[async_trait]
impl EventRepository for Events {
    async fn claim_new(&self, ids: &[Uuid], _: DateTime<Utc>) -> StoreResult<Vec<Uuid>> {
        let mut seen = self.seen.lock().unwrap();
        Ok(ids.iter().copied().filter(|id| seen.insert(*id)).collect())
    }
    async fn store_event(&self, device: Uuid, event: &Event) -> StoreResult<()> {
        self.stored.lock().unwrap().push((device, event.clone()));
        Ok(())
    }
    async fn store_counters(&self, _: Uuid, counters: &UsageCounters) -> StoreResult<()> {
        self.counters.lock().unwrap().push(*counters);
        Ok(())
    }
    async fn feedback_counts(&self, _: Uuid) -> StoreResult<(u32, u32)> {
        Ok(*self.feedback.lock().unwrap())
    }
    async fn pass_counts(&self, _: DateTime<Utc>) -> StoreResult<PassCounts> {
        Ok(PassCounts {
            warned: 20,
            warned_with_hard_brake: 2,
            unwarned: 10,
            unwarned_with_hard_brake: 4,
        })
    }
    async fn mute_counts(&self, _: DateTime<Utc>) -> StoreResult<(u32, u32)> {
        Ok((50, 5))
    }
    async fn week_one_retention_counts(&self, _: DateTime<Utc>) -> StoreResult<(u32, u32)> {
        Ok((0, 0))
    }
}

struct Roads(Vec<RoadWay>);
#[async_trait]
impl RoadNetwork for Roads {
    async fn ways_near(&self, _: Coordinate, _: f64) -> StoreResult<Vec<RoadWay>> {
        Ok(self.0.clone())
    }
}

struct Limiter(bool);
impl RateLimiter for Limiter {
    fn allow(&self, _: Uuid, _: DateTime<Utc>) -> bool {
        self.0
    }
}

// --- Helpers ---

fn process_events(hotspots: Arc<Hotspots>, events: Arc<Events>, roads: Vec<RoadWay>) -> ProcessEvents {
    ProcessEvents {
        hotspots,
        events,
        roads: Arc::new(Roads(roads)),
        clock: Arc::new(FixedClock(now())),
        plausibility: Plausibility::default(),
        matching: HotspotMatch::default(),
        consensus: Consensus::default(),
        classifier: Classifier::default(),
        review: FeedbackReview::default(),
    }
}

fn hard_brake_at(meters: f64) -> Event {
    let trace = [meters - 20.0, meters, meters + 20.0]
        .iter()
        .map(|&m| TracePoint {
            location: north(m),
            course: Some(0.0),
        })
        .collect();
    Event {
        id: Uuid::new_v4(),
        hour: now() - Duration::hours(2),
        kind: EventKind::HardBrake(HardBrake {
            course: Some(0.0),
            speed_before: Some(18.0),
            speed_after: Some(6.0),
            peak_deceleration: 0.5,
            nearest_hotspot_id: None,
            was_warned: false,
            seconds_since_warning: None,
            trace,
        }),
    }
}

fn active_hotspot(meters: f64) -> Hotspot {
    let mut hotspot = Hotspot::candidate(north(meters), Bearing::new(0.0), HotspotKind::SuddenStop, now());
    hotspot.status = HotspotStatus::Active;
    hotspot
}

// --- Tests ---

#[tokio::test]
async fn five_different_drivers_braking_at_one_spot_make_an_active_hotspot() {
    let hotspots = Arc::new(Hotspots::default());
    let process = process_events(hotspots.clone(), Arc::new(Events::default()), vec![]);

    let mut reports = Vec::new();
    for _ in 0..5 {
        reports.push(
            process
                .execute(Uuid::new_v4(), vec![hard_brake_at(500.0)])
                .await
                .unwrap(),
        );
    }

    let all = hotspots.all();
    assert_eq!(all.len(), 1, "every brake matched the first hotspot");
    assert_eq!(all[0].status, HotspotStatus::Active);
    assert_eq!(reports[0].hotspots_created, 1);
    assert_eq!(reports[3].hotspots_activated, 0);
    assert_eq!(reports[4].hotspots_activated, 1);
}

#[tokio::test]
async fn one_driver_braking_five_times_is_still_one_vote() {
    let hotspots = Arc::new(Hotspots::default());
    let process = process_events(hotspots.clone(), Arc::new(Events::default()), vec![]);
    let driver = Uuid::new_v4();

    for _ in 0..5 {
        process.execute(driver, vec![hard_brake_at(500.0)]).await.unwrap();
    }

    assert_eq!(hotspots.all()[0].status, HotspotStatus::Candidate);
}

#[tokio::test]
async fn a_new_hotspot_gets_its_type_from_the_road_shape() {
    let hotspots = Arc::new(Hotspots::default());
    let ramp = RoadWay {
        line: Polyline::new(vec![north(480.0), north(520.0)]).unwrap(),
        is_link: true,
    };
    let process = process_events(hotspots.clone(), Arc::new(Events::default()), vec![ramp]);

    process
        .execute(Uuid::new_v4(), vec![hard_brake_at(500.0)])
        .await
        .unwrap();

    assert_eq!(hotspots.all()[0].kind, HotspotKind::ShortMerge);
}

#[tokio::test]
async fn implausible_events_are_discarded_and_not_stored() {
    let events = Arc::new(Events::default());
    let process = process_events(Arc::new(Hotspots::default()), events.clone(), vec![]);
    let mut future = hard_brake_at(500.0);
    future.hour = now() + Duration::hours(5);

    let report = process.execute(Uuid::new_v4(), vec![future]).await.unwrap();

    assert_eq!(report.discarded, 1);
    assert!(events.stored.lock().unwrap().is_empty());
}

#[tokio::test]
async fn too_much_not_helpful_feedback_flags_a_hotspot() {
    let hotspots = Arc::new(Hotspots::default());
    let hotspot = active_hotspot(500.0);
    hotspots.insert(&hotspot).await.unwrap();
    let events = Arc::new(Events::default());
    // 12 warned passes, 4 of them marked not helpful: 33%.
    *events.feedback.lock().unwrap() = (12, 4);
    let process = process_events(hotspots.clone(), events, vec![]);
    let feedback = Event {
        id: Uuid::new_v4(),
        hour: now(),
        kind: EventKind::Feedback {
            helpful: false,
            not_helpful_hotspot: Some(hotspot.id),
        },
    };

    let report = process.execute(Uuid::new_v4(), vec![feedback]).await.unwrap();

    assert_eq!(report.flagged_for_review, 1);
    assert!(hotspots.all()[0].flagged_for_review);
}

#[tokio::test]
async fn lookup_returns_hotspots_with_enough_drivers_on_the_route() {
    let devices = Arc::new(Devices::default());
    let device = Uuid::new_v4();
    devices.register(device, now()).await.unwrap();
    let hotspots = Arc::new(Hotspots::default());
    let busy = active_hotspot(800.0);
    let quiet = active_hotspot(1500.0);
    hotspots.insert(&busy).await.unwrap();
    hotspots.insert(&quiet).await.unwrap();
    for _ in 0..6 {
        hotspots.record_vote(Uuid::new_v4(), busy.id, now()).await.unwrap();
    }
    hotspots.record_vote(Uuid::new_v4(), quiet.id, now()).await.unwrap();
    let lookup = LookupRouteHotspots {
        devices,
        hotspots,
        lookup: RouteLookup::default(),
        clock: Arc::new(FixedClock(now())),
    };

    let found = lookup.execute(device, vec![north(0.0), north(2000.0)]).await.unwrap();

    assert_eq!(found.len(), 1);
    assert_eq!(found[0].hotspot.id, busy.id);
    assert_eq!(found[0].driver_count, 6);
}

#[tokio::test]
async fn lookup_rejects_unknown_devices_and_broken_routes() {
    let devices = Arc::new(Devices::default());
    let known = Uuid::new_v4();
    devices.register(known, now()).await.unwrap();
    let lookup = LookupRouteHotspots {
        devices,
        hotspots: Arc::new(Hotspots::default()),
        lookup: RouteLookup::default(),
        clock: Arc::new(FixedClock(now())),
    };

    assert_eq!(
        lookup.execute(Uuid::new_v4(), vec![north(0.0), north(10.0)]).await,
        Err(LookupError::UnknownDevice)
    );
    assert_eq!(
        lookup.execute(known, vec![north(0.0)]).await,
        Err(LookupError::InvalidRoute)
    );
}

#[tokio::test]
async fn uploads_check_the_device_duplicates_and_rate_limit() {
    let devices = Arc::new(Devices::default());
    let device = Uuid::new_v4();
    devices.register(device, now()).await.unwrap();
    let events = Arc::new(Events::default());
    let accept = |allowed: bool| AcceptUpload {
        devices: devices.clone(),
        events: events.clone(),
        rate_limiter: Arc::new(Limiter(allowed)),
        clock: Arc::new(FixedClock(now())),
    };
    let batch = vec![hard_brake_at(500.0)];

    let unknown = accept(true)
        .execute(Uuid::new_v4(), Upload::Events(batch.clone()))
        .await;
    let first = accept(true).execute(device, Upload::Events(batch.clone())).await;
    let again = accept(false).execute(device, Upload::Events(batch)).await;
    let limited = accept(false)
        .execute(device, Upload::Events(vec![hard_brake_at(900.0)]))
        .await;

    assert_eq!(unknown, Err(UploadError::UnknownDevice));
    assert!(matches!(first, Ok(UploadOutcome::Accepted(events)) if events.len() == 1));
    assert_eq!(
        again,
        Ok(UploadOutcome::AlreadyReceived),
        "a retry is answered even when rate limited"
    );
    assert_eq!(limited, Err(UploadError::RateLimited));
}

#[tokio::test]
async fn counters_are_stored_right_away() {
    let devices = Arc::new(Devices::default());
    let device = Uuid::new_v4();
    devices.register(device, now()).await.unwrap();
    let events = Arc::new(Events::default());
    let accept = AcceptUpload {
        devices,
        events: events.clone(),
        rate_limiter: Arc::new(Limiter(true)),
        clock: Arc::new(FixedClock(now())),
    };
    let counters = UsageCounters {
        id: Uuid::new_v4(),
        hour: now(),
        warnings_shown: 3,
        warnings_suppressed: 0,
        mutes: 1,
        hotspots_passed: 3,
    };

    let outcome = accept.execute(device, Upload::Counters(counters)).await;

    assert_eq!(outcome, Ok(UploadOutcome::Accepted(vec![])));
    assert_eq!(events.counters.lock().unwrap().len(), 1);
}

#[tokio::test]
async fn nightly_demotes_active_hotspots_whose_votes_aged_out() {
    let hotspots = Arc::new(Hotspots::default());
    let stale = active_hotspot(500.0);
    let busy = active_hotspot(900.0);
    hotspots.insert(&stale).await.unwrap();
    hotspots.insert(&busy).await.unwrap();
    for _ in 0..5 {
        hotspots
            .record_vote(Uuid::new_v4(), stale.id, now() - Duration::days(400))
            .await
            .unwrap();
        hotspots
            .record_vote(Uuid::new_v4(), busy.id, now() - Duration::days(10))
            .await
            .unwrap();
    }
    let demote = DemoteStaleHotspots {
        hotspots: hotspots.clone(),
        consensus: Consensus::default(),
        clock: Arc::new(FixedClock(now())),
    };

    let demoted = demote.execute().await.unwrap();

    assert_eq!(demoted, 1);
    let statuses: HashMap<Uuid, HotspotStatus> = hotspots.all().into_iter().map(|h| (h.id, h.status)).collect();
    assert_eq!(statuses[&stale.id], HotspotStatus::Candidate);
    assert_eq!(statuses[&busy.id], HotspotStatus::Active);
}

#[tokio::test]
async fn metrics_turn_counts_into_rates() {
    let metrics = ComputeMetrics {
        events: Arc::new(Events::default()),
        clock: Arc::new(FixedClock(now())),
    };

    let result = metrics.execute().await.unwrap();

    assert_eq!(result.passes.warned_hard_brake_rate(), Some(0.1));
    assert_eq!(result.passes.unwarned_hard_brake_rate(), Some(0.4));
    assert_eq!(result.mute_rate, Some(0.1));
    assert_eq!(result.week_one_retention, None);
}
