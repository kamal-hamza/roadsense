-- RoadSense schema. Only what voting and the success metrics need: no routes, no trips,
-- and hard-brake positions are used to vote, then discarded.
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE devices (
    id uuid PRIMARY KEY,
    registered_at timestamptz NOT NULL
);

-- One row per device per day it uploaded, for week-one retention (success metric 3).
CREATE TABLE device_activity (
    device_id uuid NOT NULL REFERENCES devices (id) ON DELETE CASCADE,
    day date NOT NULL,
    PRIMARY KEY (device_id, day)
);

CREATE TABLE hotspots (
    id uuid PRIMARY KEY,
    kind text NOT NULL CHECK (kind IN ('sharp_curve', 'short_merge', 'sudden_stop')),
    status text NOT NULL CHECK (status IN ('candidate', 'active')),
    location geography (Point, 4326) NOT NULL,
    bearing double precision NOT NULL,
    created_at timestamptz NOT NULL,
    flagged_for_review boolean NOT NULL DEFAULT false
);
CREATE INDEX hotspots_location_idx ON hotspots USING gist (location);

-- One vote per device per hotspot; a repeat only moves voted_at.
CREATE TABLE votes (
    device_id uuid NOT NULL,
    hotspot_id uuid NOT NULL REFERENCES hotspots (id) ON DELETE CASCADE,
    voted_at timestamptz NOT NULL,
    PRIMARY KEY (device_id, hotspot_id)
);
CREATE INDEX votes_hotspot_idx ON votes (hotspot_id, voted_at);

-- Every event and counters id ever received, so retried uploads aren't counted twice.
CREATE TABLE received_ids (
    id uuid PRIMARY KEY,
    received_at timestamptz NOT NULL
);

CREATE TABLE events (
    id uuid PRIMARY KEY,
    device_id uuid NOT NULL,
    hour timestamptz NOT NULL,
    kind text NOT NULL,
    hotspot_id uuid,
    -- For hotspot passes: warned / suppressed / missed, and whether the driver braked hard.
    outcome text,
    braked_hard boolean,
    -- For feedback: true when the driver said this hotspot's warning wasn't helpful.
    not_helpful boolean
);
CREATE INDEX events_kind_hour_idx ON events (kind, hour);
CREATE INDEX events_hotspot_idx ON events (hotspot_id) WHERE hotspot_id IS NOT NULL;

-- What devices with data sharing off send instead of events.
CREATE TABLE usage_counters (
    id uuid PRIMARY KEY,
    device_id uuid NOT NULL,
    hour timestamptz NOT NULL,
    warnings_shown integer NOT NULL,
    warnings_suppressed integer NOT NULL,
    mutes integer NOT NULL,
    hotspots_passed integer NOT NULL
);
