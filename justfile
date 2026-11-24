# RoadSense commands. Run `just` to list recipes.
# Tools come from mise (`mise install`); Xcode comes from the App Store.

set shell := ["bash", "-euo", "pipefail", "-c"]

project := "RoadSense.xcodeproj"
scheme := "RoadSense"
bundle_id := "com.hkamal.RoadSense"
derived_data := "build/DerivedData"

# Overridable via environment, e.g. `SIMULATOR="iPhone 17" just test`.
# CI sets DESTINATION (e.g. "id=<udid>") directly, which takes precedence.
simulator := env("SIMULATOR", "iPhone 18 Pro")
configuration := env("CONFIGURATION", "Debug")
destination := env("DESTINATION", "platform=iOS Simulator,name=" + simulator)

xcodebuild := "xcodebuild -project " + project + " -scheme " + scheme + " -configuration " + configuration + " -derivedDataPath " + derived_data

# List available recipes
default:
    @just --list

# Open the project in Xcode
open:
    open {{ project }}

# Build the app for the iOS Simulator
build:
    {{ xcodebuild }} -destination "{{ destination }}" build | xcbeautify

# Run all tests (both packages + app) on the iOS Simulator
test:
    {{ xcodebuild }} -destination "{{ destination }}" test | xcbeautify

# Run the sensor package's tests on the Mac (fast; no simulator)
test-sensors:
    cd Packages/RoadSenseSensors && swift test --quiet

# Build, install, and launch the app in the Simulator
run: build
    xcrun simctl bootstatus "{{ simulator }}" -b >/dev/null
    open -b com.apple.iphonesimulator 2>/dev/null || echo "note: Simulator.app not found; running headless (see: just screenshot)"
    xcrun simctl install "{{ simulator }}" "{{ derived_data }}/Build/Products/{{ configuration }}-iphonesimulator/RoadSense.app"
    xcrun simctl launch "{{ simulator }}" {{ bundle_id }}

# Save a screenshot of the booted simulator
screenshot path="/tmp/roadsense.png":
    xcrun simctl io booted screenshot "{{ path }}"

# Lint Swift code (SwiftFormat check + SwiftLint strict)
lint:
    swiftformat --lint .
    swiftlint lint --strict --quiet

# Auto-format Swift code and apply SwiftLint autocorrections
format:
    swiftformat .
    swiftlint lint --fix --quiet

# Format, lint, and test (run before calling a change done)
check: format lint test-sensors test server-format server-lint server-test

# --- Backend (server/) ---

server_db_url := env("DATABASE_URL", "postgres://roadsense:roadsense@localhost:54329/roadsense")

# Start the local PostGIS database (needs Docker running)
server-db:
    docker compose -f server/compose.yaml up -d --wait

# Hotspots use the roads for their type (curve / merge) and imported crashes for their directions of travel.
# DATABASE_URL picks another database, e.g. Supabase (its Session pooler URL). OVERPASS_URL picks an Overpass
# mirror when the main server is busy, e.g. https://overpass.kumi.systems/api/interpreter.
# Import OpenStreetMap roads (default: all of Seattle) into the local database or DATABASE_URL
server-import-osm bbox="47.49,-122.44,47.74,-122.23": server-db
    mkdir -p server/data
    curl -fsSL -A "RoadSense-dev/0.1 (OSM road import)" "${OVERPASS_URL:-https://overpass-api.de/api/interpreter}" --data-urlencode 'data=[out:xml][timeout:300];(way["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|road)(_link)?$"]({{ bbox }});>;);out body;' -o server/data/roads.osm
    # The tables go in the app's `roadsense` schema; locally it may not exist until the server first runs.
    if [ -z "${DATABASE_URL:-}" ]; then docker compose -f server/compose.yaml exec -T db psql -q -U roadsense -d roadsense -c 'CREATE SCHEMA IF NOT EXISTS roadsense'; fi
    OSM_DATABASE_URL="${DATABASE_URL:-postgresql://roadsense:roadsense@db:5432/roadsense}" docker compose -f server/compose.yaml run --rm osm2pgsql

# Replaces the last import and leaves driver-reported hotspots alone. Needs a road map in the same database
# (`just server-import-osm`). DATABASE_URL picks another database, e.g. Supabase.
# Import Seattle's rear-end crashes since `since` (SDOT open data) as hotspots
server-import-collisions since="2021-01-01": server-db
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p server/data
    url="https://services.arcgis.com/ZOyb2t4B0UYuYNYH/ArcGIS/rest/services/SDOT_Collisions_All_Years_1/FeatureServer/0/query"
    # The two coding schemes the city has used: newer records fill ST_COLLISIONTYPE, older ones only SDOT_COLDESC.
    where="INCDATE >= DATE '{{ since }}' AND (ST_COLLISIONTYPE = 'Rear Ended' OR SDOT_COLDESC LIKE '%REAR END%')"
    # The service returns at most 2,000 records per request, so page through and join the pages.
    pages=()
    offset=0
    while true; do
        page="server/data/collisions-$offset.geojson"
        curl -fsS -G "$url" --data-urlencode "where=$where" --data-urlencode "outFields=LOCATION"             --data-urlencode "orderByFields=OBJECTID" --data-urlencode "resultOffset=$offset"             --data-urlencode "resultRecordCount=2000" --data-urlencode "f=geojson" -o "$page"
        pages+=("$page")
        [ "$(jq '.features | length' "$page")" -lt 2000 ] && break
        offset=$((offset + 2000))
    done
    jq -s '{type: "FeatureCollection", features: (map(.features) | add)}' "${pages[@]}" > server/data/collisions.geojson
    rm "${pages[@]}"
    echo "Downloaded $(jq '.features | length' server/data/collisions.geojson) crashes"
    cd server && DATABASE_URL="{{ server_db_url }}" cargo run -q -p roadsense-api --bin import-collisions data/collisions.geojson

# Run the API server (uses PostGIS; set ROADSENSE_IN_MEMORY=1 to run without a database). The admin token for
# /v1/metrics defaults to "dev" locally: curl -H "Authorization: Bearer dev" localhost:8080/v1/metrics
server-run: server-db
    cd server && DATABASE_URL="{{ server_db_url }}" ROADSENSE_ADMIN_TOKEN="${ROADSENSE_ADMIN_TOKEN:-dev}" cargo run -p roadsense-api

# Share the running server with your own devices over Tailscale (HTTPS, works on cellular). Needs the
# Tailscale app signed in, with MagicDNS and HTTPS certificates enabled for your tailnet.
server-share:
    #!/usr/bin/env bash
    set -euo pipefail
    ts="$(command -v tailscale || echo /Applications/Tailscale.app/Contents/MacOS/Tailscale)"
    "$ts" serve --bg http://localhost:8080
    host="$("$ts" status --json | python3 -c 'import json, sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')"
    echo "Server shared at https://$host"
    echo "On the phone: Settings > Debug > Server > paste that address > Save, then reopen RoadSense."

# Stop sharing the server over Tailscale
server-unshare:
    #!/usr/bin/env bash
    set -euo pipefail
    ts="$(command -v tailscale || echo /Applications/Tailscale.app/Contents/MacOS/Tailscale)"
    "$ts" serve reset

# Run the server's unit tests (no database needed)
server-test:
    cd server && cargo test --workspace --quiet

# Run the server's PostGIS integration tests (starts the database)
server-test-db: server-db
    cd server && DATABASE_URL="{{ server_db_url }}" cargo test --workspace --quiet -- --ignored

# Build the server's Docker image (what Render deploys)
server-docker:
    docker build -t roadsense-api server

# Check server formatting and lints
server-lint:
    cd server && cargo fmt --check && cargo clippy --workspace --all-targets --quiet -- -D warnings

# Auto-format server code
server-format:
    cd server && cargo fmt

# Remove build artifacts
clean:
    rm -rf build
