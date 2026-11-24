//! PostGIS integration tests. Run with `just server-test-db` (starts the database in Docker).

use chrono::{DateTime, Duration, Utc};
use roadsense_application::ports::{DeviceRepository, EventRepository, HotspotRepository, RoadNetwork};
use roadsense_domain::events::{Event, EventKind, PassOutcome, UsageCounters};
use roadsense_domain::geo::{Bearing, Coordinate, Polyline};
use roadsense_domain::hotspot::{Hotspot, HotspotKind, HotspotSource, HotspotStatus};
use roadsense_infrastructure::osm::PostgresRoadNetwork;
use roadsense_infrastructure::postgres::{PostgresStore, isolated_pool};
use sqlx::Executor;
use uuid::Uuid;

const ORIGIN: Coordinate = Coordinate {
    latitude: 47.6,
    longitude: -122.3,
};

fn north(meters: f64) -> Coordinate {
    ORIGIN.offset(meters, Bearing::new(0.0))
}

fn now() -> DateTime<Utc> {
    // Whole seconds, so values survive the database round trip exactly.
    DateTime::from_timestamp(Utc::now().timestamp(), 0).expect("valid time")
}

/// A store in a fresh schema; returns the schema name so the test can drop it.
async fn store() -> (PostgresStore, String) {
    let url = std::env::var("DATABASE_URL").expect("DATABASE_URL is set by `just server-test-db`");
    let schema = format!("test_{}", Uuid::new_v4().simple());
    let pool = isolated_pool(&url, &schema).await.expect("database reachable");
    (PostgresStore::with_pool(pool).await.expect("migrations run"), schema)
}

async fn drop_schema(store: &PostgresStore, schema: &str) {
    store
        .pool()
        .execute(format!("DROP SCHEMA {schema} CASCADE").as_str())
        .await
        .expect("schema dropped");
}

fn hotspot(meters: f64, status: HotspotStatus) -> Hotspot {
    let mut hotspot = Hotspot::candidate(north(meters), Bearing::new(0.0), HotspotKind::SharpCurve, now());
    hotspot.status = status;
    hotspot
}

#[tokio::test]
#[ignore = "needs PostGIS; run with `just server-test-db`"]
async fn devices_register_once_and_exist() {
    let (store, schema) = store().await;
    let device = Uuid::new_v4();

    store.register(device, now()).await.unwrap();
    store.register(device, now()).await.unwrap();

    assert!(store.exists(device).await.unwrap());
    assert!(!store.exists(Uuid::new_v4()).await.unwrap());
    drop_schema(&store, &schema).await;
}

#[tokio::test]
#[ignore = "needs PostGIS; run with `just server-test-db`"]
async fn hotspots_round_trip_and_are_found_near_points_and_routes() {
    let (store, schema) = store().await;
    let on_route = hotspot(800.0, HotspotStatus::Active);
    let candidate = hotspot(1200.0, HotspotStatus::Candidate);
    let mut far = hotspot(900.0, HotspotStatus::Active);
    far.location = north(900.0).offset(200.0, Bearing::new(90.0));
    for h in [&on_route, &candidate, &far] {
        store.insert(h).await.unwrap();
    }
    for _ in 0..3 {
        store.record_vote(Uuid::new_v4(), on_route.id, now()).await.unwrap();
    }
    let route = Polyline::new(vec![north(0.0), north(2000.0)]).unwrap();

    let near = store.near(north(805.0), 30.0).await.unwrap();
    let along = store
        .active_near_route(&route, 30.0, now() - Duration::days(365))
        .await
        .unwrap();

    assert_eq!(near.len(), 1);
    assert_eq!(near[0].id, on_route.id);
    assert!(near[0].location.distance_to(&on_route.location) < 0.01);
    assert_eq!(near[0].kind, HotspotKind::SharpCurve);
    assert_eq!(along.len(), 1, "candidates and off-route hotspots are left out");
    assert_eq!(along[0].driver_count, 3);
    drop_schema(&store, &schema).await;
}

#[tokio::test]
#[ignore = "needs PostGIS; run with `just server-test-db`"]
async fn votes_are_one_per_driver_and_age_out() {
    let (store, schema) = store().await;
    let h = hotspot(500.0, HotspotStatus::Candidate);
    store.insert(&h).await.unwrap();
    let driver = Uuid::new_v4();

    store
        .record_vote(driver, h.id, now() - Duration::days(400))
        .await
        .unwrap();
    let before_revote = store.distinct_drivers(h.id, now() - Duration::days(365)).await.unwrap();
    store.record_vote(driver, h.id, now()).await.unwrap();
    store.record_vote(driver, h.id, now()).await.unwrap();
    let after_revote = store.distinct_drivers(h.id, now() - Duration::days(365)).await.unwrap();

    assert_eq!(before_revote, 0, "a vote older than a year doesn't count");
    assert_eq!(after_revote, 1, "voting again moves the time but stays one vote");
    store.set_status(h.id, HotspotStatus::Active).await.unwrap();
    store.flag_for_review(h.id).await.unwrap();
    let active = store
        .active_with_driver_counts(now() - Duration::days(365))
        .await
        .unwrap();
    assert_eq!(active.len(), 1);
    assert!(active[0].hotspot.flagged_for_review);
    drop_schema(&store, &schema).await;
}

#[tokio::test]
#[ignore = "needs PostGIS; run with `just server-test-db`"]
async fn event_ids_are_claimed_once() {
    let (store, schema) = store().await;
    let (a, b) = (Uuid::new_v4(), Uuid::new_v4());

    let first = store.claim_new(&[a, b], now()).await.unwrap();
    let again = store.claim_new(&[a, b], now()).await.unwrap();

    assert_eq!(first.len(), 2);
    assert!(again.is_empty());
    drop_schema(&store, &schema).await;
}

#[tokio::test]
#[ignore = "needs PostGIS; run with `just server-test-db`"]
async fn metrics_queries_count_passes_mutes_feedback_and_retention() {
    let (store, schema) = store().await;
    let (driver, quiet) = (Uuid::new_v4(), Uuid::new_v4());
    let h = hotspot(500.0, HotspotStatus::Active);
    store.insert(&h).await.unwrap();
    for device in [driver, quiet] {
        store.register(device, now()).await.unwrap();
    }
    // `driver` first drove 10 days ago and again today: retained. `quiet` only drove 10 days ago.
    store.record_activity(driver, now() - Duration::days(10)).await.unwrap();
    store.record_activity(driver, now()).await.unwrap();
    store.record_activity(quiet, now() - Duration::days(10)).await.unwrap();
    let passes = [
        (
            PassOutcome::Warned {
                seconds_of_warning: 9.0,
            },
            false,
        ),
        (
            PassOutcome::Warned {
                seconds_of_warning: 8.0,
            },
            true,
        ),
        (PassOutcome::Missed, true),
        (PassOutcome::Suppressed, false),
    ];
    for (outcome, braked_hard) in passes {
        let kind = EventKind::HotspotPassed {
            hotspot_id: h.id,
            outcome,
            braked_hard,
        };
        store
            .store_event(
                driver,
                &Event {
                    id: Uuid::new_v4(),
                    hour: now(),
                    kind,
                },
            )
            .await
            .unwrap();
    }
    store
        .store_event(
            driver,
            &Event {
                id: Uuid::new_v4(),
                hour: now(),
                kind: EventKind::Muted,
            },
        )
        .await
        .unwrap();
    let feedback = EventKind::Feedback {
        helpful: false,
        not_helpful_hotspot: Some(h.id),
    };
    store
        .store_event(
            driver,
            &Event {
                id: Uuid::new_v4(),
                hour: now(),
                kind: feedback,
            },
        )
        .await
        .unwrap();
    let counters = UsageCounters {
        id: Uuid::new_v4(),
        hour: now(),
        warnings_shown: 1,
        warnings_suppressed: 0,
        mutes: 1,
        hotspots_passed: 1,
    };
    store.store_counters(quiet, &counters).await.unwrap();

    let pass_counts = store.pass_counts(now() - Duration::days(90)).await.unwrap();
    let (active, muted) = store.mute_counts(now() - Duration::days(90)).await.unwrap();
    let (new_devices, retained) = store.week_one_retention_counts(now()).await.unwrap();
    let (warned_passes, not_helpful) = store.feedback_counts(h.id).await.unwrap();

    assert_eq!((pass_counts.warned, pass_counts.warned_with_hard_brake), (2, 1));
    assert_eq!((pass_counts.unwarned, pass_counts.unwarned_with_hard_brake), (2, 1));
    assert_eq!((active, muted), (2, 2), "one muted in events, one in counters");
    assert_eq!((new_devices, retained), (2, 1));
    assert_eq!((warned_passes, not_helpful), (2, 1));
    drop_schema(&store, &schema).await;
}

#[tokio::test]
#[ignore = "needs PostGIS; run with `just server-test-db`"]
async fn road_network_is_empty_without_an_imported_map() {
    let (store, schema) = store().await;
    let roads = PostgresRoadNetwork::new(store.pool().clone());

    let ways = roads.ways_near(ORIGIN, 150.0).await.unwrap();

    assert!(ways.is_empty());
    drop_schema(&store, &schema).await;
}

#[tokio::test]
#[ignore = "needs PostGIS; run with `just server-test-db`"]
async fn a_collision_import_replaces_the_last_one_and_keeps_driver_hotspots() {
    let (store, schema) = store().await;
    let from_drivers = hotspot(100.0, HotspotStatus::Active);
    store.insert(&from_drivers).await.unwrap();
    let import = |meters: f64, crashes: u32| {
        Hotspot::from_collisions(
            north(meters),
            Bearing::new(0.0),
            HotspotKind::SuddenStop,
            crashes,
            now(),
        )
    };
    let first = [import(300.0, 6), import(600.0, 9)];
    let second = [import(900.0, 12)];

    store.replace_city_collision_hotspots(&first).await.unwrap();
    store.replace_city_collision_hotspots(&second).await.unwrap();

    let mut found = store.near(north(500.0), 1000.0).await.unwrap();
    found.sort_by_key(|h| h.location.latitude.to_bits());
    assert_eq!(found.len(), 2);
    assert_eq!(found[0].id, from_drivers.id);
    assert_eq!(found[0].source, HotspotSource::Drivers);
    assert_eq!(found[1], second[0]);
    assert_eq!(found[1].source, HotspotSource::CityCollisions { crashes: 12 });
    drop_schema(&store, &schema).await;
}

#[tokio::test]
#[ignore = "needs PostGIS; run with `just server-test-db`"]
async fn road_network_returns_only_drivable_roads_nearby() {
    let (store, schema) = store().await;
    // The shape osm2pgsql creates, with a street and a footpath along it, and a street far away.
    let line = |from: Coordinate, to: Coordinate| {
        format!(
            "ST_Transform(ST_SetSRID(ST_MakeLine(ST_MakePoint({}, {}), ST_MakePoint({}, {})), 4326), 3857)",
            from.longitude, from.latitude, to.longitude, to.latitude
        )
    };
    let east = |c: Coordinate, meters: f64| c.offset(meters, Bearing::new(90.0));
    store
        .pool()
        .execute(
            format!(
                "CREATE TABLE planet_osm_line (highway text, way geometry(LineString, 3857)); \
                 INSERT INTO planet_osm_line VALUES ('residential', {}), ('footway', {}), ('primary', {});",
                line(ORIGIN, north(300.0)),
                line(east(ORIGIN, 5.0), east(north(300.0), 5.0)),
                line(east(ORIGIN, 2000.0), east(north(300.0), 2000.0)),
            )
            .as_str(),
        )
        .await
        .unwrap();
    let roads = PostgresRoadNetwork::new(store.pool().clone());

    let ways = roads.ways_near(north(150.0), 50.0).await.unwrap();

    assert!(roads.has_map().await.unwrap());
    assert_eq!(ways.len(), 1);
    assert!(!ways[0].is_link);
    drop_schema(&store, &schema).await;
}
