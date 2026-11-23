use std::sync::Arc;

use roadsense_domain::classify::Classifier;
use roadsense_domain::events::{Event, EventKind, HardBrake, Plausibility};
use roadsense_domain::hotspot::{Hotspot, HotspotStatus};
use roadsense_domain::rules::{Consensus, FeedbackReview, HotspotMatch};
use uuid::Uuid;

use crate::ports::{Clock, EventRepository, HotspotRepository, RoadNetwork, StoreResult};

/// What one batch of events did, for logs and tests.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct ProcessReport {
    pub discarded: u32,
    pub votes: u32,
    pub hotspots_created: u32,
    pub hotspots_activated: u32,
    pub flagged_for_review: u32,
}

/// Turns accepted events into votes, hotspots, and metric data (activity diagram 7).
pub struct ProcessEvents {
    pub hotspots: Arc<dyn HotspotRepository>,
    pub events: Arc<dyn EventRepository>,
    pub roads: Arc<dyn RoadNetwork>,
    pub clock: Arc<dyn Clock>,
    pub plausibility: Plausibility,
    pub matching: HotspotMatch,
    pub consensus: Consensus,
    pub classifier: Classifier,
    pub review: FeedbackReview,
}

/// How far around a new hotspot to fetch roads for classifying it.
const ROAD_SEARCH_RADIUS: f64 = 150.0;

impl ProcessEvents {
    pub async fn execute(&self, device: Uuid, events: Vec<Event>) -> StoreResult<ProcessReport> {
        let now = self.clock.now();
        let mut report = ProcessReport::default();
        for event in events {
            // Bad GPS, broken clocks, and faked data are dropped before they can vote.
            if self.plausibility.check(&event, now).is_err() {
                report.discarded += 1;
                continue;
            }
            self.events.store_event(device, &event).await?;
            match &event.kind {
                EventKind::HardBrake(brake) => self.vote(device, brake, &mut report).await?,
                EventKind::Feedback {
                    not_helpful_hotspot: Some(hotspot),
                    ..
                } => {
                    self.review_feedback(*hotspot, &mut report).await?;
                }
                _ => {}
            }
        }
        Ok(report)
    }

    /// One vote per driver: match the brake to a hotspot (or create a candidate) and maybe activate it.
    async fn vote(&self, device: Uuid, brake: &HardBrake, report: &mut ProcessReport) -> StoreResult<()> {
        let Some((location, bearing)) = brake.location() else {
            report.discarded += 1;
            return Ok(());
        };
        let nearby = self.hotspots.near(location, self.matching.radius).await?;
        let hotspot = match nearby
            .into_iter()
            .find(|hotspot| self.matching.matches(hotspot, &location, bearing))
        {
            Some(existing) => existing,
            None => {
                let ways = self.roads.ways_near(location, ROAD_SEARCH_RADIUS).await?;
                let kind = self.classifier.classify(&location, bearing, &ways);
                let created = Hotspot::candidate(location, bearing, kind, self.clock.now());
                self.hotspots.insert(&created).await?;
                report.hotspots_created += 1;
                created
            }
        };
        self.hotspots.record_vote(device, hotspot.id, self.clock.now()).await?;
        report.votes += 1;

        let since = self.consensus.window_start(self.clock.now());
        let drivers = self.hotspots.distinct_drivers(hotspot.id, since).await?;
        if hotspot.status == HotspotStatus::Candidate && self.consensus.is_met(drivers) {
            self.hotspots.set_status(hotspot.id, HotspotStatus::Active).await?;
            report.hotspots_activated += 1;
        }
        Ok(())
    }

    /// Flags a hotspot when too many warned drivers said its warning wasn't helpful.
    async fn review_feedback(&self, hotspot: Uuid, report: &mut ProcessReport) -> StoreResult<()> {
        let (warned_passes, not_helpful) = self.events.feedback_counts(hotspot).await?;
        // Feedback names only the unhelpful warning, so warned passes stand in for the replies.
        let helpful = warned_passes.saturating_sub(not_helpful);
        if self.review.needs_review(helpful, not_helpful) {
            self.hotspots.flag_for_review(hotspot).await?;
            report.flagged_for_review += 1;
        }
        Ok(())
    }
}
