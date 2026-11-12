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

# Run unit tests on the iOS Simulator
test:
    {{ xcodebuild }} -destination "{{ destination }}" test | xcbeautify

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
check: format lint test

# Remove build artifacts
clean:
    rm -rf build
