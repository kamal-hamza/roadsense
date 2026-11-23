//! HTTP handlers. They translate wire DTOs to domain types, call one use case, and map the result to a status.

use axum::Router;
use axum::extract::{Json, State};
use axum::http::{HeaderMap, StatusCode};
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
        .route("/health", get(|| async { StatusCode::OK }))
        .route("/v1/devices", post(register_device))
        .route("/v1/routes/hotspots", post(route_hotspots))
        .route("/v1/events", post(upload_events))
        .route("/v1/metrics", get(metrics))
        .with_state(state)
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

/// Internal: the success metrics. Put it behind auth or a private network before deploying.
async fn metrics(State(state): State<AppState>) -> Response {
    match state.compute_metrics.execute().await {
        Ok(metrics) => Json(MetricsResponse::from(metrics)).into_response(),
        Err(store_error) => store_unavailable(&store_error),
    }
}
