# AGENTS.md

Guidance for AI coding agents working in this repository.

> **Read [`CODING_GUIDELINES.md`](CODING_GUIDELINES.md) before writing code.** It
> holds the full rules, drawn from Apple's and Swift.org's guidance, plus this
> project's layered architecture. This file covers orientation and workflow. The
> guidelines win if the two disagree.

## Project

RoadSense is a native iOS app written in Swift with SwiftUI.

- **Bundle ID:** `com.hkamal.RoadSense` (tests: `com.hkamal.RoadSenseTests`)
- **Deployment target:** iOS 26.0, iPhone + iPad
- **Toolchain:** Xcode 27, Swift 6 language mode, strict concurrency
- **Architecture:** layered / Clean Architecture, one Swift module per layer (below)
- **Dependencies:** no third-party packages. Ask before adding one. If approved,
  add it to the layer that needs it in `Packages/RoadSenseKit/Package.swift`, never
  to the app target directly. No CocoaPods or Carthage.

## Architecture (summary)

The full rules are in [`CODING_GUIDELINES.md` §1](CODING_GUIDELINES.md#1-architecture-layers).
The structure mirrors a .NET layered solution: each layer is a separate module in
the local package `Packages/RoadSenseKit`, so illegal references fail to compile.

```
Presentation ──► Application ──► Domain ◄── Application ◄── Infrastructure
 (frontend)       (use cases,    (entities,                  (backend: storage,
  SwiftUI, VMs     ports)         rules)                      network, sensors)

RoadSense app target = composition root (like Program.cs): wires everything.
```

| Layer | Path | Holds | May import |
|---|---|---|---|
| Domain | `Packages/RoadSenseKit/Sources/Domain` | Entities, value objects, domain errors | `Foundation` only |
| Application | `.../Sources/Application` | Use cases, ports (protocols) | `Domain`, `Foundation` |
| Infrastructure | `.../Sources/Infrastructure` | Port implementations (SwiftData, network, Core Location) | `Application`, `Domain`, Apple frameworks |
| Presentation | `.../Sources/Presentation` | SwiftUI views, `@Observable` view models | `Application`, `Domain`, SwiftUI |
| Composition root | `RoadSense/App` | `@main`, `AppContainer` | everything |

Non-negotiables:

- Dependencies point inward. **Presentation never imports Infrastructure.**
- Concrete Infrastructure types are constructed **only** in `RoadSense/App/AppContainer.swift`.
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
| `just test`       | Run all tests (every layer + app) on the Simulator      |
| `just run`        | Build, install, and launch the app in the Simulator     |
| `just screenshot` | Screenshot the booted simulator to `/tmp/roadsense.png` |
| `just lint`       | `swiftformat --lint` + `swiftlint --strict` (incl. layer guards) |
| `just format`     | Auto-format and apply SwiftLint autocorrections         |
| `just check`      | format + lint + test                                    |
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
4. Go through the checklist in [`CODING_GUIDELINES.md` §10](CODING_GUIDELINES.md#10-checklist-before-finishing).

## Layout

```
RoadSense.xcodeproj/             Xcode project + shared `RoadSense` scheme (runs all test targets)
RoadSense/                       App target = composition root
  App/RoadSenseApp.swift         @main entry point
  App/AppContainer.swift         Wires Infrastructure into use cases (only place that does)
  Resources/Assets.xcassets      App icon, accent color
RoadSenseTests/                  Composition-root smoke tests
Packages/RoadSenseKit/           Local Swift package: one module per layer
  Package.swift                  Layer dependency graph + concurrency settings
  Sources/Domain/                Entities/, Errors/
  Sources/Application/           Ports/, UseCases/
  Sources/Infrastructure/        Repositories/ (later: Persistence/, Networking/, Services/)
  Sources/Presentation/          Features/<Feature>/, Shared/, Composition/
  Tests/<Layer>Tests/            One Swift Testing target per layer
.github/workflows/ci.yml         CI: lint, release build, tests
mise.toml                        Tool versions (only)
justfile                         Project commands
.swiftformat, .swiftlint.yml     Formatter/linter config (+ architecture guard rules)
CODING_GUIDELINES.md             Coding rules: read before writing code
```

## Rules and gotchas

- **Don't edit `project.pbxproj` to add files.** `RoadSense/` and `RoadSenseTests/`
  are file-system synchronized groups, and SwiftPM picks up any file under
  `Packages/RoadSenseKit/Sources/<Layer>/` automatically. Only touch the project
  file for build settings, new targets, or linking package products, and keep
  edits minimal.
- **New package test targets** must also be added to the `RoadSense` scheme's
  `<Testables>` (`RoadSense.xcodeproj/xcshareddata/xcschemes/RoadSense.xcscheme`),
  or `just test` won't run them.
- **Concurrency defaults differ by layer.** The app target and Presentation are
  `MainActor` by default. Domain, Application, and Infrastructure are nonisolated
  and must be `Sendable`. See [`CODING_GUIDELINES.md` §4](CODING_GUIDELINES.md#4-concurrency).
- **No `Info.plist` file.** It's generated (`GENERATE_INFOPLIST_FILE = YES`).
  Add keys as `INFOPLIST_KEY_*` build settings on the app target (both Debug and
  Release), e.g. `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription`.
- **Entitlements and capabilities** (background location, push, etc.) need a
  `.entitlements` file plus `CODE_SIGN_ENTITLEMENTS`. Tell the user when a change
  needs Apple Developer portal setup.
- **Code signing:** automatic, no `DEVELOPMENT_TEAM` committed. Simulator builds
  don't need a team. Don't hardcode a team ID.
- **Formatting** is owned by SwiftFormat. It also rewrites test names into raw
  identifiers (`` `does the thing` ``). Run `just format` rather than fighting it.
- **CI** runs on the `xcode-27` GitHub runner and picks the first available iPhone
  simulator, so don't depend on a specific device name in tests.
