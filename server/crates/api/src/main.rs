//! RoadSense API server: the composition root. Builds concrete storage and wires the use cases.

use std::net::SocketAddr;
use std::sync::Arc;

use chrono::{Duration as ChronoDuration, NaiveTime, Utc};
use roadsense_api::composition::{Storage, build_state};
use roadsense_api::{AppState, router};
use roadsense_infrastructure::osm::PostgresRoadNetwork;
use roadsense_infrastructure::postgres::PostgresStore;
use std::io::IsTerminal;

use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        // Colors only in a terminal; hosted log viewers show the escape codes as junk.
        .with_ansi(std::io::stdout().is_terminal())
        .init();

    let storage = storage().await?;
    let state = build_state(storage, std::env::var("ROADSENSE_ADMIN_TOKEN").ok());
    tokio::spawn(nightly_demotion(state.clone()));

    let address = bind_address()?;
    let listener = tokio::net::TcpListener::bind(address).await?;
    tracing::info!(%address, "RoadSense API listening");
    axum::serve(listener, router(state))
        .with_graceful_shutdown(shutdown_signal())
        .await?;
    Ok(())
}

/// PostGIS from DATABASE_URL, or the in-memory store when ROADSENSE_IN_MEMORY=1 (data is lost on restart).
async fn storage() -> Result<Storage, Box<dyn std::error::Error>> {
    if std::env::var("ROADSENSE_IN_MEMORY").is_ok_and(|value| value == "1") {
        tracing::warn!("using the in-memory store; nothing is saved");
        return Ok(Storage::in_memory());
    }
    let url = std::env::var("DATABASE_URL").map_err(|_| "set DATABASE_URL, or ROADSENSE_IN_MEMORY=1")?;
    let store = Arc::new(PostgresStore::connect(&url).await?);
    let roads = Arc::new(PostgresRoadNetwork::new(store.pool().clone()));
    Ok(Storage {
        devices: store.clone(),
        hotspots: store.clone(),
        events: store.clone(),
        roads,
        health: store,
    })
}

/// BIND_ADDRESS if set; else all interfaces on PORT (what Render and Cloud Run provide); else :8080.
fn bind_address() -> Result<SocketAddr, Box<dyn std::error::Error>> {
    if let Ok(address) = std::env::var("BIND_ADDRESS") {
        return Ok(address.parse()?);
    }
    let port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|port| port.parse().ok())
        .unwrap_or(8080);
    Ok(SocketAddr::from(([0, 0, 0, 0], port)))
}

/// Runs the demotion once at startup (a free host may have slept through 03:00), then every day at 03:00 UTC.
async fn nightly_demotion(state: AppState) {
    match state.demote_stale_hotspots.execute().await {
        Ok(demoted) => tracing::info!(demoted, "startup demotion finished"),
        Err(store_error) => tracing::error!(%store_error, "startup demotion failed"),
    }
    loop {
        let now = Utc::now();
        let three_am = NaiveTime::from_hms_opt(3, 0, 0).unwrap_or_default();
        let mut next = now.date_naive().and_time(three_am).and_utc();
        if next <= now {
            next += ChronoDuration::days(1);
        }
        let wait = (next - now).to_std().unwrap_or_default();
        tokio::time::sleep(wait).await;
        match state.demote_stale_hotspots.execute().await {
            Ok(demoted) => tracing::info!(demoted, "nightly demotion finished"),
            Err(store_error) => tracing::error!(%store_error, "nightly demotion failed"),
        }
    }
}

async fn shutdown_signal() {
    // If the signal handler can't be installed, keep serving until killed.
    if tokio::signal::ctrl_c().await.is_err() {
        std::future::pending::<()>().await;
    }
    tracing::info!("shutting down");
}
