//! HTTP round trips against the in-memory store: the wire format, status codes, and the voting flow.

use std::time::Duration;

use axum::Router;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use roadsense_api::composition::{Storage, build_state};
use roadsense_api::dto::RouteHotspotsResponse;
use roadsense_api::router;
use serde_json::{Value, json};
use tower::ServiceExt;
use uuid::Uuid;

const ADMIN_TOKEN: &str = "test-admin-token";

fn app() -> Router {
    router(build_state(Storage::in_memory(), Some(ADMIN_TOKEN.into())))
}

async fn send(app: &Router, method: &str, path: &str, device: Option<Uuid>, body: Value) -> (StatusCode, Value) {
    send_with(app, method, path, device, None, body).await
}

async fn send_with(
    app: &Router,
    method: &str,
    path: &str,
    device: Option<Uuid>,
    bearer: Option<&str>,
    body: Value,
) -> (StatusCode, Value) {
    let mut request = Request::builder()
        .method(method)
        .uri(path)
        .header("content-type", "application/json");
    if let Some(token) = bearer {
        request = request.header("authorization", format!("Bearer {token}"));
    }
    if let Some(device) = device {
        request = request.header("x-device-id", device.to_string());
    }
    let response = app
        .clone()
        .oneshot(request.body(Body::from(body.to_string())).unwrap())
        .await
        .unwrap();
    let status = response.status();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    let json = if bytes.is_empty() {
        Value::Null
    } else {
        serde_json::from_slice(&bytes).unwrap()
    };
    (status, json)
}

async fn register(app: &Router) -> Uuid {
    let device = Uuid::new_v4();
    let (status, _) = send(app, "POST", "/v1/devices", None, json!({ "deviceId": device })).await;
    assert_eq!(status, StatusCode::CREATED);
    device
}

/// A point `meters` north of downtown Seattle.
fn north(meters: f64) -> (f64, f64) {
    (47.6062 + meters / 111_320.0, -122.3321)
}

fn route() -> Value {
    let points: Vec<Value> = [0.0, 1000.0, 2000.0]
        .iter()
        .map(|&m| json!({ "latitude": north(m).0, "longitude": north(m).1 }))
        .collect();
    json!({ "points": points })
}

fn hard_brake(meters: f64) -> Value {
    let trace: Vec<Value> = [meters - 20.0, meters, meters + 20.0]
        .iter()
        .map(|&m| json!({ "latitude": north(m).0, "longitude": north(m).1, "course": 0.0 }))
        .collect();
    json!({
        "id": Uuid::new_v4(),
        "hour": chrono::Utc::now().to_rfc3339(),
        "type": "hardBrake",
        "course": 0.0,
        "speedBefore": 17.0,
        "speedAfter": 5.0,
        "peakDeceleration": 0.5,
        "nearestHotspotId": null,
        "wasWarned": false,
        "secondsSinceWarning": null,
        "trace": trace,
    })
}

fn upload(events: Vec<Value>) -> Value {
    json!({ "batchId": Uuid::new_v4(), "createdAt": chrono::Utc::now().to_rfc3339(), "events": events })
}

#[tokio::test]
async fn five_drivers_braking_at_one_spot_put_it_on_everyones_route() {
    let app = app();
    let checker = register(&app).await;
    let (status, body) = send(&app, "POST", "/v1/routes/hotspots", Some(checker), route()).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["hotspots"], json!([]));

    for _ in 0..5 {
        let driver = register(&app).await;
        let (status, _) = send(
            &app,
            "POST",
            "/v1/events",
            Some(driver),
            upload(vec![hard_brake(1200.0)]),
        )
        .await;
        assert_eq!(status, StatusCode::ACCEPTED);
    }

    // Uploads are processed in the background after the 202, so give them a moment.
    let mut found = None;
    for _ in 0..50 {
        let (_, body) = send(&app, "POST", "/v1/routes/hotspots", Some(checker), route()).await;
        let response: RouteHotspotsResponse = serde_json::from_value(body).unwrap();
        if !response.hotspots.is_empty() {
            found = Some(response);
            break;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    let response = found.expect("the hotspot became active");
    assert_eq!(response.hotspots.len(), 1);
    assert_eq!(response.hotspots[0].driver_count, 5);
    assert!((response.hotspots[0].distance_along_route - 1200.0).abs() < 5.0);
}

#[tokio::test]
async fn the_wire_format_uses_camel_case() {
    let app = app();
    let device = register(&app).await;
    let (_, body) = send_with(&app, "GET", "/v1/metrics", None, Some(ADMIN_TOKEN), Value::Null).await;
    assert!(body.get("warnedPasses").is_some(), "{body}");

    let passed = json!({
        "id": Uuid::new_v4(), "hour": chrono::Utc::now().to_rfc3339(), "type": "hotspotPassed",
        "hotspotId": Uuid::new_v4(), "outcome": "warned", "secondsOfWarning": 9.5, "brakedHard": false,
    });
    let feedback = json!({
        "id": Uuid::new_v4(), "hour": chrono::Utc::now().to_rfc3339(), "type": "feedback",
        "helpful": false, "hotspotId": Uuid::new_v4(),
    });
    let muted = json!({ "id": Uuid::new_v4(), "hour": chrono::Utc::now().to_rfc3339(), "type": "muted" });
    let turn = json!({
        "id": Uuid::new_v4(), "hour": chrono::Utc::now().to_rfc3339(), "type": "sharpTurn",
        "peakLateralAcceleration": 0.42,
        "trace": [{ "latitude": 47.6062, "longitude": -122.3321, "course": 10.0 }],
    });
    let (status, _) = send(
        &app,
        "POST",
        "/v1/events",
        Some(device),
        upload(vec![passed, feedback, muted, turn]),
    )
    .await;
    assert_eq!(status, StatusCode::ACCEPTED);
}

#[tokio::test]
async fn status_codes_tell_the_app_what_to_do() {
    let app = app();
    let device = register(&app).await;
    let batch = upload(vec![hard_brake(500.0)]);

    let (no_device, _) = send(&app, "POST", "/v1/events", None, batch.clone()).await;
    let (unknown, _) = send(&app, "POST", "/v1/events", Some(Uuid::new_v4()), batch.clone()).await;
    let (first, _) = send(&app, "POST", "/v1/events", Some(device), batch.clone()).await;
    let (again, _) = send(&app, "POST", "/v1/events", Some(device), batch).await;
    let (bad_route, _) = send(
        &app,
        "POST",
        "/v1/routes/hotspots",
        Some(device),
        json!({ "points": [{ "latitude": 1, "longitude": 1 }] }),
    )
    .await;
    let both = json!({
        "batchId": Uuid::new_v4(), "createdAt": chrono::Utc::now().to_rfc3339(), "events": [],
        "counters": { "id": Uuid::new_v4(), "hour": chrono::Utc::now().to_rfc3339(), "warningsShown": 0,
                      "warningsSuppressed": 0, "mutes": 0, "hotspotsPassed": 0 },
    });
    let (malformed, _) = send(&app, "POST", "/v1/events", Some(device), both).await;

    assert_eq!(no_device, StatusCode::UNAUTHORIZED);
    assert_eq!(unknown, StatusCode::UNAUTHORIZED);
    assert_eq!(first, StatusCode::ACCEPTED);
    assert_eq!(again, StatusCode::OK, "already received");
    assert_eq!(bad_route, StatusCode::BAD_REQUEST);
    assert_eq!(malformed, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn too_many_uploads_are_rate_limited() {
    let app = app();
    let device = register(&app).await;

    let mut statuses = Vec::new();
    for _ in 0..31 {
        let (status, _) = send(
            &app,
            "POST",
            "/v1/events",
            Some(device),
            upload(vec![hard_brake(500.0)]),
        )
        .await;
        statuses.push(status);
    }

    assert!(statuses[..30].iter().all(|status| *status == StatusCode::ACCEPTED));
    assert_eq!(statuses[30], StatusCode::TOO_MANY_REQUESTS);
}

#[tokio::test]
async fn counters_are_accepted_when_data_sharing_is_off() {
    let app = app();
    let device = register(&app).await;
    let counters = json!({
        "batchId": Uuid::new_v4(), "createdAt": chrono::Utc::now().to_rfc3339(),
        "counters": { "id": Uuid::new_v4(), "hour": chrono::Utc::now().to_rfc3339(), "warningsShown": 2,
                      "warningsSuppressed": 0, "mutes": 1, "hotspotsPassed": 2 },
    });

    let (status, _) = send(&app, "POST", "/v1/events", Some(device), counters).await;

    assert_eq!(status, StatusCode::ACCEPTED);
}

#[tokio::test]
async fn internal_endpoints_need_the_admin_token() {
    let app = app();

    let (no_token, _) = send(&app, "GET", "/v1/metrics", None, Value::Null).await;
    let (wrong, _) = send_with(&app, "GET", "/v1/metrics", None, Some("nope"), Value::Null).await;
    let (right, _) = send_with(&app, "GET", "/v1/metrics", None, Some(ADMIN_TOKEN), Value::Null).await;
    let (demote, body) = send_with(
        &app,
        "POST",
        "/v1/admin/demote-stale-hotspots",
        None,
        Some(ADMIN_TOKEN),
        Value::Null,
    )
    .await;

    assert_eq!(no_token, StatusCode::NOT_FOUND);
    assert_eq!(wrong, StatusCode::NOT_FOUND);
    assert_eq!(right, StatusCode::OK);
    assert_eq!(demote, StatusCode::OK);
    assert_eq!(body["demoted"], 0);
}

#[tokio::test]
async fn without_a_configured_token_internal_endpoints_are_off() {
    let app = router(build_state(Storage::in_memory(), None));

    let (status, _) = send_with(&app, "GET", "/v1/metrics", None, Some(""), Value::Null).await;

    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn health_checks_storage() {
    let (status, _) = send(&app(), "GET", "/health", None, Value::Null).await;

    assert_eq!(status, StatusCode::OK);
}
