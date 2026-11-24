//! Reads Seattle's collision records (SDOT Collisions, GeoJSON from the city's ArcGIS service) into crash records.
//! `just server-import-collisions` downloads only the crash types worth warning about; this keeps every point.

use roadsense_domain::collisions::CrashRecord;
use roadsense_domain::geo::{Bearing, Coordinate};
use serde::Deserialize;

#[derive(Deserialize)]
struct FeatureCollection {
    features: Vec<Feature>,
}

#[derive(Deserialize)]
struct Feature {
    geometry: Option<Geometry>,
    #[serde(default)]
    properties: Properties,
}

#[derive(Deserialize)]
struct Geometry {
    /// GeoJSON order: longitude, then latitude.
    coordinates: Vec<f64>,
}

#[derive(Deserialize, Default)]
struct Properties {
    #[serde(rename = "LOCATION")]
    location: Option<String>,
}

/// The crashes in a GeoJSON download. Records without a usable position are skipped.
/// - Errors: when the text isn't a GeoJSON feature collection.
pub fn parse(geojson: &str) -> Result<Vec<CrashRecord>, serde_json::Error> {
    let collection: FeatureCollection = serde_json::from_str(geojson)?;
    Ok(collection
        .features
        .into_iter()
        .filter_map(|feature| {
            let coordinates = feature.geometry?.coordinates;
            let location = Coordinate::new(*coordinates.get(1)?, *coordinates.first()?);
            location.is_valid().then(|| CrashRecord {
                location,
                heading: feature.properties.location.as_deref().and_then(heading_from_location),
            })
        })
        .collect())
}

/// The direction of travel in an address like "AURORA AVE N NB BETWEEN ...", if it names one.
fn heading_from_location(location: &str) -> Option<Bearing> {
    location.split_whitespace().find_map(|word| match word {
        "NB" => Some(Bearing::new(0.0)),
        "EB" => Some(Bearing::new(90.0)),
        "SB" => Some(Bearing::new(180.0)),
        "WB" => Some(Bearing::new(270.0)),
        _ => None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_positions_and_headings_and_skips_records_without_a_position() {
        let geojson = r#"{"type":"FeatureCollection","features":[
            {"type":"Feature","geometry":{"type":"Point","coordinates":[-122.33,47.60]},
             "properties":{"LOCATION":"1ST AV S BR NB BETWEEN POINT A AND SR509 NB"}},
            {"type":"Feature","geometry":{"type":"Point","coordinates":[-122.34,47.61]},
             "properties":{"LOCATION":"7TH AVE AND JAMES ST"}},
            {"type":"Feature","geometry":null,"properties":{"LOCATION":"UNKNOWN"}}
        ]}"#;

        let records = parse(geojson).unwrap();

        assert_eq!(records.len(), 2);
        assert_eq!(records[0].location, Coordinate::new(47.60, -122.33));
        assert_eq!(records[0].heading, Some(Bearing::new(0.0)));
        assert_eq!(records[1].heading, None);
    }

    #[test]
    fn only_whole_words_name_a_direction() {
        assert_eq!(heading_from_location("WESTLAKE AVE N AND NEWTON ST"), None);
        assert_eq!(heading_from_location("I5 SB OFF RP"), Some(Bearing::new(180.0)));
    }
}
