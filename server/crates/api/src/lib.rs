//! RoadSense HTTP API: routes, wire DTOs, and the shared state the handlers use.

pub mod composition;
pub mod dto;
pub mod routes;
pub mod state;

pub use routes::router;
pub use state::AppState;
