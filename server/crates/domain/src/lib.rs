//! RoadSense backend domain: hotspots, votes, events, and the rules that turn hard brakes into warnings.
//! See docs/MVP_USE_CASE_1.md §5 for the numbers and the reasoning behind them.

pub mod classify;
pub mod collisions;
pub mod curves;
pub mod events;
pub mod geo;
pub mod hotspot;
pub mod lookup;
pub mod metrics;
pub mod rules;
