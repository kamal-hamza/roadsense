//! HTTP handlers. They translate wire DTOs to domain types, call one use case, and map the result to a status.

use std::time::Instant;

use axum::Router;
use axum::extract::{Json, Request, State};
use axum::http::{HeaderMap, StatusCode, header};
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use roadsense_application::ports::StoreError;
use roadsense_application::use_cases::{LookupError, Upload, UploadError, UploadOutcome};
use uuid::Uuid;

use crate::dto::{
    ErrorResponse, MetricsResponse, RegisterDeviceRequest, RouteHotspotDto, RouteHotspotsRequest,
    RouteHotspotsResponse, UploadRequest,
};
use crate::state::AppState;

/// The header carrying the app's anonymous device id.
pub const DEVICE_HEADER: &str = "x-device-id";

pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/health", get(health))
        .route("/v1/devices", post(register_device))
        .route("/v1/routes/hotspots", post(route_hotspots))
        .route("/v1/events", post(upload_events))
        .route("/v1/metrics", get(metrics))
        .route("/v1/admin/demote-stale-hotspots", post(demote_stale_hotspots))
        .layer(middleware::from_fn(log_request))
        .with_state(state)
}

/// Logs each request's method, path, status, time taken, and which device sent it.
async fn log_request(request: Request, next: Next) -> Response {
    let method = request.method().clone();
    let path = request.uri().path().to_owned();
    // The first block of the device id is enough to tell devices apart in the logs.
    let device = request
        .headers()
        .get(DEVICE_HEADER)
        .and_then(|value| value.to_str().ok())
        .map_or_else(|| "-".to_owned(), |id| id.chars().take(8).collect());
    let started = Instant::now();
    let response = next.run(request).await;
    let status = response.status().as_u16();
    let elapsed_ms = started.elapsed().as_millis();
    // The keep-alive pings /health every few minutes, so keep it out of the default log level.
    if path == "/health" {
        tracing::debug!(%method, path, status, elapsed_ms, device, "request");
    } else {
        tracing::info!(%method, path, status, elapsed_ms, device, "request");
    }
    response
}

/// An error reply with a short message.
fn error(status: StatusCode, message: &str) -> Response {
    (
        status,
        Json(ErrorResponse {
            error: message.to_owned(),
        }),
    )
        .into_response()
}

fn store_unavailable(store_error: &StoreError) -> Response {
    tracing::error!(%store_error, "storage failed");
    error(StatusCode::SERVICE_UNAVAILABLE, "storage unavailable; try again later")
}

fn device_id(headers: &HeaderMap) -> Option<Uuid> {
    headers.get(DEVICE_HEADER)?.to_str().ok()?.parse().ok()
}

async fn register_device(State(state): State<AppState>, Json(request): Json<RegisterDeviceRequest>) -> Response {
    match state.register_device.execute(request.device_id).await {
        Ok(()) => StatusCode::CREATED.into_response(),
        Err(store_error) => store_unavailable(&store_error),
    }
}

async fn route_hotspots(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<RouteHotspotsRequest>,
) -> Response {
    let Some(device) = device_id(&headers) else {
        return error(StatusCode::UNAUTHORIZED, "missing or invalid device id");
    };
    let points = request.points.into_iter().map(Into::into).collect();
    match state.lookup_route_hotspots.execute(device, points).await {
        Ok(hotspots) => {
            let hotspots = hotspots.into_iter().map(RouteHotspotDto::from).collect();
            Json(RouteHotspotsResponse { hotspots }).into_response()
        }
        Err(LookupError::UnknownDevice) => error(StatusCode::UNAUTHORIZED, "unknown device"),
        Err(LookupError::InvalidRoute) => error(StatusCode::BAD_REQUEST, "the route needs at least two valid points"),
        Err(LookupError::Store(store_error)) => store_unavailable(&store_error),
    }
}

async fn upload_events(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<UploadRequest>,
) -> Response {
    let Some(device) = device_id(&headers) else {
        return error(StatusCode::UNAUTHORIZED, "missing or invalid device id");
    };
    let upload = match (request.events, request.counters) {
        (Some(events), None) => Upload::Events(events.into_iter().map(Into::into).collect()),
        (None, Some(counters)) => Upload::Counters(counters.into()),
        _ => return error(StatusCode::BAD_REQUEST, "send either events or counters"),
    };
    match state.accept_upload.execute(device, upload).await {
        Ok(UploadOutcome::Accepted(events)) => {
            // Reply now; voting and metrics happen in the background so the phone isn't kept waiting.
            if !events.is_empty() {
                let process = state.process_events.clone();
                tokio::spawn(async move {
                    match process.execute(device, events).await {
                        Ok(report) => tracing::info!(?report, "processed upload"),
                        Err(store_error) => tracing::error!(%store_error, "processing an upload failed"),
                    }
                });
            }
            StatusCode::ACCEPTED.into_response()
        }
        Ok(UploadOutcome::AlreadyReceived) => StatusCode::OK.into_response(),
        Err(UploadError::UnknownDevice) => error(StatusCode::UNAUTHORIZED, "unknown device"),
        Err(UploadError::RateLimited) => error(StatusCode::TOO_MANY_REQUESTS, "too many uploads; try again later"),
        Err(UploadError::Store(store_error)) => store_unavailable(&store_error),
    }
}

/// OK when storage answers. Pinging this also keeps a free hosted database from pausing.
async fn health(State(state): State<AppState>) -> Response {
    match state.health.check().await {
        Ok(()) => StatusCode::OK.into_response(),
        Err(store_error) => store_unavailable(&store_error),
    }
}

/// Whether the request carries `Authorization: Bearer <admin token>`. Off (always false) when no token is set.
fn is_admin(state: &AppState, headers: &HeaderMap) -> bool {
    let Some(expected) = state.admin_token.as_deref() else {
        return false;
    };
    let given = headers
        .get(header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.strip_prefix("Bearer "))
        .unwrap_or_default();
    // Compare every byte so the time taken doesn't reveal how much of the token matched.
    given.len() == expected.len()
        && given
            .bytes()
            .zip(expected.bytes())
            .fold(0, |diff, (a, b)| diff | (a ^ b))
            == 0
}

/// Internal: the success metrics. Needs the admin token.
async fn metrics(State(state): State<AppState>, headers: HeaderMap) -> Response {
    if !is_admin(&state, &headers) {
        return error(StatusCode::NOT_FOUND, "not found");
    }
    match state.compute_metrics.execute().await {
        Ok(metrics) => Json(MetricsResponse::from(metrics)).into_response(),
        Err(store_error) => store_unavailable(&store_error),
    }
}

/// Internal: runs the stale-hotspot demotion now, for a scheduler to call on hosts that sleep. Needs the admin token.
async fn demote_stale_hotspots(State(state): State<AppState>, headers: HeaderMap) -> Response {
    if !is_admin(&state, &headers) {
        return error(StatusCode::NOT_FOUND, "not found");
    }
    match state.demote_stale_hotspots.execute().await {
        Ok(demoted) => Json(serde_json::json!({ "demoted": demoted })).into_response(),
        Err(store_error) => store_unavailable(&store_error),
    }
}
