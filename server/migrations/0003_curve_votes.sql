-- Drivers who cornered hard through a hotspot while staying on one road: evidence it's a curve the map missed.
-- One per device per hotspot, like votes; enough of them relabel a sudden-stop hotspot as a sharp curve.
CREATE TABLE curve_votes (
    device_id uuid NOT NULL,
    hotspot_id uuid NOT NULL REFERENCES hotspots (id) ON DELETE CASCADE,
    voted_at timestamptz NOT NULL,
    PRIMARY KEY (device_id, hotspot_id)
);
CREATE INDEX curve_votes_hotspot_idx ON curve_votes (hotspot_id, voted_at);
