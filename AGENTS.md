# AGENTS.md

Guidance for AI coding agents working in this repository.

> **Read [`CODING_GUIDELINES.md`](CODING_GUIDELINES.md) before writing code.** It
> holds the full rules, drawn from Apple's and Swift.org's guidance, plus this
> project's layered architecture. This file covers orientation and workflow. The
> guidelines win if the two disagree.
>
> **Working on sensors, trip recording, background location, event detection, or
> spoken alerts?** Read [`docs/SENSORS.md`](docs/SENSORS.md) first. It covers the
> chosen Apple APIs, the background and permission constraints, the algorithms,
> and the test strategy.

## Project

RoadSense is a native iOS app written in Swift with SwiftUI.

- **Bundle ID:** `com.hkamal.RoadSense` (tests: `com.hkamal.RoadSenseTests`)
- **Deployment target:** iOS 26.0, iPhone + iPad
- **Toolchain:** Xcode 27, Swift 6 language mode, strict concurrency
- **Architecture:** layered / Clean Architecture, one Swift module per layer, plus a
  self-contained sensor package (below)
- **Dependencies:** no third-party packages. Ask before adding one. If approved,
  add it to the layer that needs it in `Packages/RoadSenseKit/Package.swift`, never
  to the app target directly. No CocoaPods or Carthage.

## Architecture (summary)

The full rules are in [`CODING_GUIDELINES.md` §1](CODING_GUIDELINES.md#1-architecture-layers).
Two local packages. Each module is a separate Swift target, so illegal references
fail to compile (like separate `.csproj` projects in .NET).

```
Packages/RoadSenseKit (the app's layers)
  Presentation ──► Application ──► Domain ◄── Application ◄── Infrastructure
   (frontend)       (use cases,    (Trip,                      (backend: trip
    SwiftUI, VMs     ports)         rules)                      storage, later network)

Packages/RoadSenseSensors (self-contained; knows nothing about trips or UI)
  SensorDevice ──► SensorRecording ──► SensorCore ◄── DriveSimulation
  (Core Motion/     (recorder +        (pure algorithms)  (synthetic drives)
   Location, logs)   ports)

RoadSense app target = composition root (like Program.cs): wires both together.
```

| Module | Path | Holds | May import |
|---|---|---|---|
| Domain | `Packages/RoadSenseKit/Sources/Domain` | `Trip`, domain errors | `Foundation`, `SensorCore` |
| Application | `.../RoadSenseKit/Sources/Application` | Use cases (`RecordTripUseCase`, ...), ports | `Domain`, `SensorCore`, `SensorRecording` |
| Infrastructure | `.../RoadSenseKit/Sources/Infrastructure` | Port implementations (trip storage) | `Application`, `Domain`, Apple frameworks except sensors |
| Presentation | `.../RoadSenseKit/Sources/Presentation` | SwiftUI views, `@Observable` view models | `Application`, `Domain`, `SensorCore`, `SensorRecording`, SwiftUI |
| SensorCore | `Packages/RoadSenseSensors/Sources/SensorCore` | Readings, vehicle frame estimator, event detectors, trip state machine | `Foundation` only |
| SensorRecording | `.../RoadSenseSensors/Sources/SensorRecording` | `SensorRecorder`, ports `SensorSource` / `SensorLogStore` | `SensorCore`, `Foundation` |
| SensorDevice | `.../RoadSenseSensors/Sources/SensorDevice` | Live/replay/simulated sensor sources, file sensor logs | Core Motion, Core Location, anything above |
| DriveSimulation | `.../RoadSenseSensors/Sources/DriveSimulation` | Synthetic drives for tests and the simulator | `SensorCore` |
| Composition root | `RoadSense/App` | `@main`, `AppContainer` | everything |

Non-negotiables:

- Dependencies point inward. **Presentation never imports Infrastructure.**
- Concrete Infrastructure and `SensorDevice` types are constructed **only** in
  `RoadSense/App/AppContainer.swift`. Nothing in RoadSenseKit imports `SensorDevice`,
  Core Motion, or Core Location.
- **RoadSenseSensors stays self-contained.** It never imports RoadSenseKit and has
  no notion of trips, storage, or UI. `RecordTripUseCase` turns its
  `RecordingSummary` into a `Trip`.
- SensorCore, SensorRecording, and DriveSimulation stay pure (Foundation only), so
  `just test-sensors` runs on the Mac in under a second. Apple sensor code goes in
  SensorDevice, wrapped in `#if os(iOS)`.
- Never add a `Package.swift` dependency to get around a layering error. Move the
  code, or add a port.
- Build features inside-out: Domain → Application (port + use case) →
  Infrastructure → Presentation → wire in `AppContainer` → tests per layer.
  The example **Trips** feature shows every step. It's a placeholder, so replace it
  once real features exist.

## Tooling

- **mise installs tools, and only tools.** `mise.toml` pins `just`, `swiftformat`,
  `swiftlint`, and `xcbeautify`. Run `mise install` once. Add new CLI tools there,
  not through Homebrew. Don't define mise tasks.
- **just runs commands.** Every project command is a recipe in `justfile`. Use the
  recipes rather than calling `xcodebuild` by hand. CI runs the same recipes.
- Xcode is not managed by mise.

If a tool shows "command not found", the shell doesn't have mise activated. Run
recipes as `mise exec -- just <recipe>`.

| Command           | What it does                                            |
| ----------------- | ------------------------------------------------------- |
| `just`            | List recipes                                            |
| `just build`      | Build for the iOS Simulator                             |
| `just test`       | Run all tests (both packages + app) on the Simulator    |
| `just test-sensors` | Run the sensor package's tests on the Mac with `swift test` (fast) |
| `just run`        | Build, install, and launch the app in the Simulator     |
| `just screenshot` | Screenshot the booted simulator to `/tmp/roadsense.png` |
| `just lint`       | `swiftformat --lint` + `swiftlint --strict` (incl. layer guards) |
| `just format`     | Auto-format and apply SwiftLint autocorrections         |
| `just check`      | format + lint + test-sensors + test                     |
| `just clean`      | Delete `build/`                                         |
| `just open`       | Open the project in Xcode                               |

Environment overrides:

- `SIMULATOR="iPhone 17"`: simulator name (default `iPhone 18 Pro`)
- `DESTINATION="id=<udid>"`: full xcodebuild destination; takes precedence over `SIMULATOR`
- `CONFIGURATION=Release`: build configuration (default `Debug`)

Build output goes to `build/DerivedData` (gitignored).

### Verifying changes

Before you call a change done:

1. `just check` passes: format, lint (including architecture guards), and all tests.
2. The build has zero compiler warnings.
3. For UI changes, run `just run`, then `just screenshot`, and look at the image.
   This machine may not have Simulator.app, so the simulator can run headless.
   Screenshots still work.
   - To see the live recording screen without tapping, relaunch with the debug hook:
     `xcrun simctl launch booted com.hkamal.RoadSense -autoStartRecording`. In the
     simulator, sensors come from a simulated drive (`SimulatedSensorSource`).
4. When working on sensor algorithms, iterate with `just test-sensors`. Add test
   cases using `SyntheticDrive` (known physics) or replayed real logs (`ReplaySensorSource`).
5. Go through the checklist in [`CODING_GUIDELINES.md` §10](CODING_GUIDELINES.md#10-checklist-before-finishing).

## Layout

```
RoadSense.xcodeproj/             Xcode project + shared `RoadSense` scheme (runs all test targets)
RoadSense/                       App target = composition root
  App/RoadSenseApp.swift         @main entry point
  App/AppContainer.swift         Wires everything (only place that creates concrete types)
  Info.plist                     Only keys with no build setting (UIBackgroundModes, file sharing)
  Resources/Assets.xcassets      App icon, accent color
RoadSenseTests/                  Composition-root smoke tests
Packages/RoadSenseKit/           The app's layers, one module each
  Sources/Domain/                Entities/ (Trip), Errors/
  Sources/Application/           Ports/, UseCases/ (ListTrips, RecordTrip, FindSensorLog)
  Sources/Infrastructure/        Persistence/ (FileTripRepository), Repositories/
  Sources/Presentation/          Features/{Recording,Trips}/, Shared/, Composition/
  Tests/<Layer>Tests/            One Swift Testing target per layer
Packages/RoadSenseSensors/       Self-contained sensor package
  Sources/SensorCore/            Readings/, Detection/ (frame estimator, detectors, pipeline), Trips/
  Sources/SensorRecording/       SensorRecorder, Ports/
  Sources/SensorDevice/          Sensors/ (live, replay, simulated), Logging/ (JSONL sensor logs)
  Sources/DriveSimulation/       SyntheticDrive, DriveSegment, PhoneOrientation
  Tests/Sensor*Tests/            Run on the Mac (`just test-sensors`) and in the simulator
.github/workflows/ci.yml         CI: lint, release build, tests
mise.toml                        Tool versions (only)
justfile                         Project commands
.swiftformat, .swiftlint.yml     Formatter/linter config (+ architecture guard rules)
CODING_GUIDELINES.md             Coding rules: read before writing code
docs/SENSORS.md                  Sensor/background/event-detection design (Apple-docs based)
```

## Rules and gotchas

- **Don't edit `project.pbxproj` to add files.** `RoadSense/` and `RoadSenseTests/`
  are file-system synchronized groups, and SwiftPM picks up any file under
  `Packages/*/Sources/<Module>/` automatically. Only touch the project
  file for build settings, new targets, or linking package products, and keep
  edits minimal.
- **New package test targets** must also be added to the `RoadSense` scheme's
  `<Testables>` (`RoadSense.xcodeproj/xcshareddata/xcschemes/RoadSense.xcscheme`),
  or `just test` won't run them.
- **Concurrency defaults differ by layer.** The app target and Presentation are
  `MainActor` by default. Everything else (including the whole sensor package) is
  nonisolated and must be `Sendable`. Callbacks handed to Core Motion must be
  built outside actors and marked `@Sendable` (see `LiveSensorSource`), or they
  trap at runtime. See [`CODING_GUIDELINES.md` §4](CODING_GUIDELINES.md#4-concurrency).
- **Info.plist is mostly generated** (`GENERATE_INFOPLIST_FILE = YES`). Add keys as
  `INFOPLIST_KEY_*` build settings on the app target (both Debug and Release), e.g.
  the existing `INFOPLIST_KEY_NSMotionUsageDescription`. Only keys that have no
  build setting go in `RoadSense/Info.plist` (currently `UIBackgroundModes` and
  `UIFileSharingEnabled`). That file is excluded from resource copying in the
  project; keep it that way.
- **Sensors need a real iPhone.** The simulator has no motion sensors, so it runs a
  simulated drive. Background recording behavior can only be checked on a device.
- **Entitlements and capabilities** (background location, push, etc.) need a
  `.entitlements` file plus `CODE_SIGN_ENTITLEMENTS`. Tell the user when a change
  needs Apple Developer portal setup.
- **Code signing:** automatic, no `DEVELOPMENT_TEAM` committed. Simulator builds
  don't need a team. Don't hardcode a team ID.
- **Formatting** is owned by SwiftFormat. It also rewrites test names into raw
  identifiers (`` `does the thing` ``). Run `just format` rather than fighting it.
- **CI** runs on the `xcode-27` GitHub runner and picks the first available iPhone
  simulator, so don't depend on a specific device name in tests.
