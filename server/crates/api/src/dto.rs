//! The JSON wire format (v1). It lives only here and in the app's Infrastructure/Networking; domain types
//! never go on the wire directly. camelCase keys, ISO-8601 dates.

use chrono::{DateTime, Utc};
use roadsense_domain::events::{Event, EventKind, HardBrake, PassOutcome, TracePoint, UsageCounters};
use roadsense_domain::geo::Coordinate;
use roadsense_domain::hotspot::{HotspotKind, HotspotSource, RouteHotspot};
use roadsense_domain::metrics::SuccessMetrics;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RegisterDeviceRequest {
    pub device_id: Uuid,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct PointDto {
    pub latitude: f64,
    pub longitude: f64,
}

impl From<PointDto> for Coordinate {
    fn from(point: PointDto) -> Self {
        Coordinate::new(point.latitude, point.longitude)
    }
}

/// The route to check. It's used for this request only and never stored.
#[derive(Debug, Deserialize)]
pub struct RouteHotspotsRequest {
    pub points: Vec<PointDto>,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum HotspotKindDto {
    SharpCurve,
    ShortMerge,
    SuddenStop,
}

impl From<HotspotKind> for HotspotKindDto {
    fn from(kind: HotspotKind) -> Self {
        match kind {
            HotspotKind::SharpCurve => Self::SharpCurve,
            HotspotKind::ShortMerge => Self::ShortMerge,
            HotspotKind::SuddenStop => Self::SuddenStop,
        }
    }
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RouteHotspotDto {
    pub id: Uuid,
    pub kind: HotspotKindDto,
    pub latitude: f64,
    pub longitude: f64,
    pub bearing: f64,
    pub driver_count: u32,
    pub distance_along_route: f64,
    /// Crashes the city recorded here, for hotspots from its collision records; `null` for driver-reported ones.
    #[serde(default)]
    pub reported_crashes: Option<u32>,
}

impl From<RouteHotspot> for RouteHotspotDto {
    fn from(route_hotspot: RouteHotspot) -> Self {
        let hotspot = route_hotspot.hotspot;
        Self {
            id: hotspot.id,
            kind: hotspot.kind.into(),
            latitude: hotspot.location.latitude,
            longitude: hotspot.location.longitude,
            bearing: hotspot.bearing.degrees(),
            driver_count: route_hotspot.driver_count,
            distance_along_route: route_hotspot.distance_along_route,
            reported_crashes: match hotspot.source {
                HotspotSource::Drivers => None,
                HotspotSource::CityCollisions { crashes } => Some(crashes),
            },
        }
    }
}

#[derive(Debug, Serialize, Deserialize)]
pub struct RouteHotspotsResponse {
    pub hotspots: Vec<RouteHotspotDto>,
}

/// An upload: events, or only counters when the driver turned data sharing off. Exactly one is set.
#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UploadRequest {
    pub batch_id: Uuid,
    pub created_at: DateTime<Utc>,
    #[serde(default)]
    pub events: Option<Vec<EventDto>>,
    #[serde(default)]
    pub counters: Option<CountersDto>,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EventDto {
    pub id: Uuid,
    pub hour: DateTime<Utc>,
    #[serde(flatten)]
    pub kind: EventKindDto,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase", rename_all_fields = "camelCase")]
pub enum EventKindDto {
    HardBrake {
        course: Option<f64>,
        speed_before: Option<f64>,
        speed_after: Option<f64>,
        peak_deceleration: f64,
        nearest_hotspot_id: Option<Uuid>,
        was_warned: bool,
        seconds_since_warning: Option<f64>,
        trace: Vec<TracePointDto>,
    },
    HotspotPassed {
        hotspot_id: Uuid,
        outcome: PassOutcomeDto,
        seconds_of_warning: Option<f64>,
        braked_hard: bool,
    },
    WarningShown {
        hotspot_ids: Vec<Uuid>,
        speed: Option<f64>,
    },
    WarningSuppressed {
        hotspot_ids: Vec<Uuid>,
    },
    Muted,
    Unmuted,
    Feedback {
        helpful: bool,
        hotspot_id: Option<Uuid>,
    },
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum PassOutcomeDto {
    Warned,
    Suppressed,
    Missed,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct TracePointDto {
    pub latitude: f64,
    pub longitude: f64,
    pub course: Option<f64>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CountersDto {
    pub id: Uuid,
    pub hour: DateTime<Utc>,
    pub warnings_shown: u32,
    pub warnings_suppressed: u32,
    pub mutes: u32,
    pub hotspots_passed: u32,
}

impl From<EventDto> for Event {
    fn from(dto: EventDto) -> Self {
        let kind = match dto.kind {
            EventKindDto::HardBrake {
                course,
                speed_before,
                speed_after,
                peak_deceleration,
                nearest_hotspot_id,
                was_warned,
                seconds_since_warning,
                trace,
            } => EventKind::HardBrake(HardBrake {
                course,
                speed_before,
                speed_after,
                peak_deceleration,
                nearest_hotspot_id,
                was_warned,
                seconds_since_warning,
                trace: trace
                    .into_iter()
                    .map(|point| TracePoint {
                        location: Coordinate::new(point.latitude, point.longitude),
                        course: point.course,
                    })
                    .collect(),
            }),
            EventKindDto::HotspotPassed {
                hotspot_id,
                outcome,
                seconds_of_warning,
                braked_hard,
            } => {
                let outcome = match outcome {
                    PassOutcomeDto::Warned => PassOutcome::Warned {
                        seconds_of_warning: seconds_of_warning.unwrap_or(0.0),
                    },
                    PassOutcomeDto::Suppressed => PassOutcome::Suppressed,
                    PassOutcomeDto::Missed => PassOutcome::Missed,
                };
                EventKind::HotspotPassed {
                    hotspot_id,
                    outcome,
                    braked_hard,
                }
            }
            EventKindDto::WarningShown { hotspot_ids, speed } => EventKind::WarningShown { hotspot_ids, speed },
            EventKindDto::WarningSuppressed { hotspot_ids } => EventKind::WarningSuppressed { hotspot_ids },
            EventKindDto::Muted => EventKind::Muted,
            EventKindDto::Unmuted => EventKind::Unmuted,
            EventKindDto::Feedback { helpful, hotspot_id } => EventKind::Feedback {
                helpful,
                not_helpful_hotspot: if helpful { None } else { hotspot_id },
            },
        };
        Event {
            id: dto.id,
            hour: dto.hour,
            kind,
        }
    }
}

impl From<CountersDto> for UsageCounters {
    fn from(dto: CountersDto) -> Self {
        Self {
            id: dto.id,
            hour: dto.hour,
            warnings_shown: dto.warnings_shown,
            warnings_suppressed: dto.warnings_suppressed,
            mutes: dto.mutes,
            hotspots_passed: dto.hotspots_passed,
        }
    }
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MetricsResponse {
    pub warned_passes: u32,
    pub warned_hard_brake_rate: Option<f64>,
    pub unwarned_passes: u32,
    pub unwarned_hard_brake_rate: Option<f64>,
    pub mute_rate: Option<f64>,
    pub week_one_retention: Option<f64>,
}

impl From<SuccessMetrics> for MetricsResponse {
    fn from(metrics: SuccessMetrics) -> Self {
        Self {
            warned_passes: metrics.passes.warned,
            warned_hard_brake_rate: metrics.passes.warned_hard_brake_rate(),
            unwarned_passes: metrics.passes.unwarned,
            unwarned_hard_brake_rate: metrics.passes.unwarned_hard_brake_rate(),
            mute_rate: metrics.mute_rate,
            week_one_retention: metrics.week_one_retention,
        }
    }
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ErrorResponse {
    pub error: String,
}
