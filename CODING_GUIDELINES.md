# Coding Guidelines

Rules for writing Swift in RoadSense. They come from Apple's and Swift.org's own
guidance, adapted to this project's layered architecture. **Agents must follow
these rules.** If a rule blocks you, say so instead of quietly working around it.

Rules are written as **MUST** (enforced or non-negotiable), **SHOULD** (default;
deviate only with a reason stated in the PR or a code comment), and **AVOID**.

Contents:

1. [Architecture: layers](#1-architecture-layers)
2. [Naming and API design](#2-naming-and-api-design)
3. [SwiftUI and data flow](#3-swiftui-and-data-flow)
4. [Concurrency](#4-concurrency)
5. [Error handling](#5-error-handling)
6. [Testing](#6-testing)
7. [Accessibility and HIG](#7-accessibility-and-hig)
8. [Privacy and permissions](#8-privacy-and-permissions)
9. [Documentation comments](#9-documentation-comments)
10. [Checklist before finishing](#10-checklist-before-finishing)
11. [Sources](#11-sources)

---

## 1. Architecture: layers

RoadSense uses a **layered (Clean Architecture) design**, the same shape as a
typical .NET solution. Apple recommends [organizing app code into local Swift
packages][local-packages] for modularity. We use that to give every layer its own
**Swift module**, so the compiler enforces the dependency rules, the way separate
`.csproj` projects do in .NET.

### 1.1 The layers

```
              ┌──────────────────────────────┐
              │  RoadSense (app target)      │  Composition root
              │  RoadSense/App/              │  (Program.cs)
              └──────┬────────────────┬──────┘
                     │                │
          ┌──────────▼───────┐  ┌─────▼────────────┐
 frontend │  Presentation    │  │  Infrastructure  │  backend
          │  SwiftUI, VMs    │  │  storage, APIs,  │
          └──────────┬───────┘  │  device sensors  │
                     │          └─────┬────────────┘
                     │                │
              ┌──────▼────────────────▼──────┐
              │  Application                 │  use cases + ports
              └──────────────┬───────────────┘
                             │
              ┌──────────────▼───────────────┐
              │  Domain                      │  entities, rules
              └──────────────────────────────┘
```

| Layer | Module / location | .NET equivalent | Contains | May import |
|---|---|---|---|---|
| **Domain** | `Packages/RoadSenseKit/Sources/Domain` | `RoadSense.Domain` | Entities, value objects, domain errors, pure business rules | `Foundation` only |
| **Application** | `.../Sources/Application` | `RoadSense.Application` | Use cases, **ports** (protocols for repositories/services), DTOs | `Domain`, `Foundation` |
| **Infrastructure** | `.../Sources/Infrastructure` | `RoadSense.Infrastructure` | Port implementations: SwiftData, `URLSession`, Core Location, Core Motion, Keychain | `Application`, `Domain`, any Apple framework |
| **Presentation** | `.../Sources/Presentation` | `RoadSense.Web` / UI project | SwiftUI views, `@Observable` view models, navigation, preview fakes | `Application`, `Domain`, SwiftUI, MapKit, etc. |
| **Composition root** | `RoadSense/App` (app target) | `Program.cs` / DI registration | `@main` app, `AppContainer` wiring concrete types | Everything |

"Backend" here means the non-UI layers inside the app (Domain, Application,
Infrastructure). "Frontend" is Presentation. If a separate server is added later,
it gets its own folder and the same four layers.

### 1.2 The dependency rule (MUST)

- **Dependencies point inward only:** Presentation → Application → Domain, and
  Infrastructure → Application → Domain. Domain depends on nothing.
- **Presentation MUST NOT import Infrastructure**, and Infrastructure MUST NOT
  import Presentation. They only meet in the composition root.
- **Domain and Application MUST import only `Foundation`** (and the layers below
  them). No SwiftUI, UIKit, SwiftData, Core Location, Combine, etc.
- **Concrete Infrastructure types are only created in `RoadSense/App/AppContainer.swift`.**

How it's enforced:

1. `Packages/RoadSenseKit/Package.swift` declares target dependencies, so an
   illegal `import` between layers fails to compile.
2. SwiftLint custom rules in `.swiftlint.yml` block Apple framework imports in
   Domain/Application and persistence frameworks in Presentation. The compiler
   can't catch those.

**Never "fix" a layering error by adding a dependency in `Package.swift`.** Move the
code to the right layer, or add a port.

### 1.3 How the layers talk

| .NET concept | Swift in this repo |
|---|---|
| `interface ITripRepository` in Application | `protocol TripRepository: Sendable` in `Application/Ports/` |
| Repository class in Infrastructure | `actor` / `struct` / `final class` conforming to the port, in `Infrastructure/` |
| MediatR handler / service method | Use case `struct` in `Application/UseCases/`, one per operation, exposing `callAsFunction()` |
| `IServiceCollection` DI | **Manual constructor injection.** `AppContainer` builds `AppDependencies`. No DI framework, no service locators, no singletons. |
| EF Core entities | SwiftData `@Model` classes live **only** in Infrastructure, mapped to Domain structs at the boundary |
| DTO / ViewModel | Application DTOs (`struct`) for use-case I/O; Presentation view models (`@Observable`) for UI state |
| xUnit test project per layer | Test target per layer in `Packages/RoadSenseKit/Tests/` |

The example "Trips" feature shows the whole flow:

```
Domain/Entities/Trip.swift                            entity + invariants
Application/Ports/TripRepository.swift                port (protocol)
Application/UseCases/ListTripsUseCase.swift           use case
Infrastructure/Repositories/InMemoryTripRepository.swift  implementation
Presentation/Features/Trips/TripListViewModel.swift   UI state
Presentation/Features/Trips/TripListView.swift        view
Presentation/Composition/AppDependencies.swift        what Presentation needs
RoadSense/App/AppContainer.swift                      wiring (composition root)
```

### 1.4 Adding a feature (recipe)

Work from the inside out:

1. **Domain:** add or extend entities in `Domain/Entities/` and errors in
   `Domain/Errors/`. Enforce invariants in initializers (see `Trip.init`).
2. **Application:** add a port in `Application/Ports/` if the feature needs data
   or a device or system service. Add a use case in `Application/UseCases/`.
3. **Infrastructure:** implement the port in the matching folder:
   `Repositories/`, `Services/`, `Persistence/`, or `Networking/`.
4. **Presentation:** add `Presentation/Features/<Feature>/` with the view, the view
   model, and any subviews. Add the use case to `AppDependencies`.
5. **Composition root:** construct the implementation and use case in `AppContainer`.
6. **Tests:** at least one test per layer you touched (see §6).

### 1.5 Folder conventions

```
Packages/RoadSenseKit/Sources/
  Domain/          Entities/  ValueObjects/  Errors/  Services/ (pure domain logic)
  Application/     Ports/  UseCases/  DTOs/
  Infrastructure/  Repositories/  Persistence/  Networking/  Services/ (device/system adapters)
  Presentation/    Features/<Feature>/  Shared/ (reusable views, styles, preview support)  Composition/
RoadSense/
  App/             RoadSenseApp.swift, AppContainer.swift
  Resources/       Assets.xcassets, PrivacyInfo.xcprivacy, string catalogs
```

- One primary type per file, and the file is named after it (`TripListView.swift`).
- Group Presentation **by feature**, not by type. Don't use a global `Views/`
  folder or a global `ViewModels/` folder.
- SwiftPM picks up new files under `Sources/<Layer>/` automatically, and Xcode
  picks up new files under `RoadSense/`. Don't edit `project.pbxproj` to add files.

### 1.6 Access control

- **SHOULD** default to `internal`. Mark something `public` only when another
  layer needs it. A small public surface keeps the layer boundaries meaningful.
- Presentation exposes only `RootView` and `AppDependencies`. Views and view
  models stay `internal`, and tests reach them with `@testable import`.
- **MUST** mark classes `final` unless they're designed for subclassing.

---

## 2. Naming and API design

From the [Swift API Design Guidelines][api-guidelines]. The headline rule is
**clarity at the point of use**: clarity matters more than brevity.

### Naming

- **MUST** use `UpperCamelCase` for types and protocols and `lowerCamelCase` for
  everything else. Treat acronyms as words unless they're conventionally all caps:
  `tripID`, `urlSession`, `utf8Bytes`.
- **MUST** include every word needed to avoid ambiguity, and **omit needless words**,
  especially words that repeat type information:
  `trips.remove(trip)`, not `trips.removeTrip(trip)`.
- **MUST** name variables and parameters by **role**, not type: `let destination: Coordinate`, not `let coordinate`.
- **SHOULD** make call sites read as English phrases: `trip.distance(to: other)`.
- Side-effect-free methods read as **nouns** (`trip.duration`, `sorted()`). Methods
  with side effects read as **imperative verbs** (`save(_:)`, `startRecording()`).
- Mutating/non-mutating pairs: `sort()` / `sorted()`, `append(_:)` / `appending(_:)`,
  `formUnion(_:)` / `union(_:)`.
- Booleans read as assertions: `isRecording`, `hasPermission`, `canSave`.
- Protocols that describe *what something is* are nouns (`TripRepository`).
  Capabilities use `-able`/`-ible`/`-ing` (`Locating`, `Identifiable`).
- Factory methods start with `make`: `AppContainer.makeLive()`.
- **AVOID** abbreviations (`configuration`, not `cfg`) and obscure terms. Use
  established terms of art only with their usual meaning.
- Use cases are named `<Verb><Noun>UseCase` (`ListTripsUseCase`, `StartTripUseCase`).
  Ports are named after what they provide (`TripRepository`, `LocationProvider`).

### Argument labels and parameters

- Omit the first label when it forms a grammatical phrase with the base name
  (`save(_ trip:)`). Use a preposition label when the first argument starts a
  prepositional phrase (`distance(to:)`).
- Label all other arguments. Label tuple members and name closure parameters.
- **SHOULD** prefer default arguments over families of overloads, and put
  defaulted parameters last.
- **AVOID** overloading only on return type.

### General

- Prefer methods and computed properties over free functions.
- Document the complexity of any computed property that isn't O(1).
- Prefer `struct` and `enum` (value types) by default. Use `class` when you need
  identity or shared mutable state (`@Observable` view models, SwiftData models),
  and `actor` for shared mutable state across concurrency domains.
- **AVOID** force unwraps (`!`), `try!`, and `as!` outside tests. Use `guard let`
  and handle the failure.
- **AVOID** `Any`/`AnyObject`. Use generics or protocols with `some`/`any`, and
  prefer `some` when the concrete type is fixed.

---

## 3. SwiftUI and data flow

From Apple's [Managing model data in your app][model-data] and
[Migrating to the Observable macro][observable-migration].

### Observation (MUST)

- **MUST** use the `@Observable` macro for observable reference types. **MUST NOT**
  use `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`, or
  `@EnvironmentObject` in new code.
- Don't conform to the `Observable` protocol by hand. Always use the macro. Apple
  notes the protocol alone adds no observation.
- Use `@ObservationIgnored` for stored properties that shouldn't trigger view
  updates, such as caches and injected dependencies that never change.

| Need | Use |
|---|---|
| View **owns** an observable model or simple value state | `@State private var model = Model()` |
| View **reads** a model passed in | plain `let model: Model`. No wrapper needed. |
| View needs **bindings** (`$model.name`) to a model it doesn't own | `@Bindable var model: Model`, or `@Bindable var model = model` inside `body` |
| Model shared deep in the hierarchy | `.environment(model)` + `@Environment(Model.self) private var model` |
| Model **may be absent** from the environment | `@Environment(Model.self) private var model: Model?`. Non-optional crashes if missing. |

- `@State` and `@Environment` properties **MUST** be `private`.
- `@State` initializers can run more than once, and only the first value is kept.
  Keep them free of side effects, and don't expect them to track changes from the
  parent.

### Views

- **Views are dumb.** A view renders state and forwards user intent to its view
  model. **MUST NOT** call repositories, `URLSession`, SwiftData, or system
  services from a view. Go through a use case.
- View models are `@Observable final class` in Presentation. They receive
  **use cases** (not repositories) through `init`, expose `private(set)` state,
  and have intent methods (`load()`, `save()`).
- Model loading and error states explicitly (an `enum State`, as in
  `TripListViewModel`) instead of several independent optionals and booleans.
- Start async work with `.task { await viewModel.load() }`. It's cancelled
  automatically when the view disappears. **AVOID** `Task { }` in `onAppear`.
- Keep `body` small. Extract subviews into their own `View` structs rather than
  large computed properties or `func`s returning views. That gives SwiftUI finer
  update tracking.
- **AVOID** expensive work in `body` (sorting, formatting, filtering big
  collections). Do it in the view model or use case.
- Use `NavigationStack` with value-based `navigationDestination(for:)`. Don't use
  `NavigationView`.
- Use system components (`List`, `Form`, `ContentUnavailableView`, `Label`, `ProgressView`)
  before building custom ones.
- Format values with `FormatStyle` (`Text(date, format: .dateTime...)`,
  `Measurement.formatted(.measurement(usage: .road))`) so output follows the
  user's locale and units. Don't build strings by hand.

### Previews

- **MUST** keep a `#Preview` for every screen-level view, covering the main states
  (loaded, empty, error) when cheap.
- Previews use fakes from `Presentation/Shared/PreviewSupport.swift`,
  because Presentation can't import Infrastructure. Don't wrap preview fakes in
  `#if DEBUG`: `#Preview` bodies are type-checked in Release builds too.

### Strings and assets

- User-facing text goes through SwiftUI's `LocalizedStringKey` initializers
  (`Text("No Trips")`) so the String Catalog picks it up. Don't hardcode strings
  in view models. Return domain values and let the view format them.
- Prefer SF Symbols and semantic system colors (`.primary`, `.secondary`, `.tint`).
  Custom colors go in `Assets.xcassets` with light, dark, and high-contrast variants.

---

## 4. Concurrency

From Apple's [Adopting strict concurrency in Swift 6 apps][swift6], the
[Swift migration guide][migration-guide], and Swift Evolution
[SE-0466 (default actor isolation)][se-0466] and [SE-0461][se-0461].

### Project settings (already configured)

| Target | Language mode | Default isolation | Why |
|---|---|---|---|
| App target, **Presentation** | Swift 6 | `MainActor` | UI code is effectively single-threaded. SE-0466 removes false-positive data-race errors for it. |
| **Domain, Application, Infrastructure** | Swift 6 | nonisolated | Business logic and I/O must be callable from any context and be provably data-race free. |

All targets enable `NonisolatedNonsendingByDefault` (SE-0461): non-isolated `async`
functions run on the **caller's** actor unless marked `@concurrent`.

### Rules

- **MUST** compile with zero concurrency warnings. Fix the root cause.
  **MUST NOT** silence warnings with `@unchecked Sendable`, `nonisolated(unsafe)`,
  or `@preconcurrency` without a comment explaining why it's safe.
- Domain entities, DTOs, and errors **MUST** be `Sendable` value types (`struct`/`enum`).
- Ports **MUST** be `protocol X: Sendable` with `async` (and usually `throws`) methods.
- Shared mutable state in Infrastructure **MUST** be an `actor`, or a type whose
  state is protected and documented. No unprotected `static var`.
- Use `@concurrent` for CPU-heavy work (sensor processing, parsing large files) so
  it runs off the caller's actor. Don't use `DispatchQueue` in new code.
- Prefer structured concurrency (`async let`, `withTaskGroup`) over unstructured
  `Task { }`. When you must create a `Task`, keep its handle and cancel it when
  the owner goes away.
- Check for cancellation in long-running loops (`try Task.checkCancellation()`).
- Use `AsyncStream`/`AsyncSequence` for streams of events (location updates, motion
  samples) exposed by ports. Don't expose Combine publishers or delegate callbacks
  across layers.
- Wrap delegate- or callback-based Apple APIs (e.g. `CLLocationManagerDelegate`) in
  Infrastructure, and expose them as `async` functions or `AsyncStream`.

---

## 5. Error handling

- Each layer defines **meaningful error types** (`enum ...Error: Error, Sendable`).
  Domain errors describe rule violations (`TripError.negativeDistance`).
  Infrastructure maps framework errors (`URLError`, SwiftData errors) to errors
  that Application understands. **MUST NOT** leak framework error types through ports.
- Use **typed throws** (`throws(TripError)`) where a function can only fail in a
  known, closed set of ways (Domain invariants). Use untyped `throws` at boundaries
  where errors are open-ended (I/O).
- Presentation turns errors into user-facing state (`State.failed`), with copy the
  user can act on. **MUST NOT** silently swallow errors (`try?` that discards a
  failure the user should know about).
- Use `precondition`/`fatalError` only for programmer errors that can't be
  recovered from, never for user input or I/O.
- Log with `os.Logger` (subsystem `com.hkamal.RoadSense`, one category per area).
  Don't use `print`. **MUST NOT** log personal data such as precise locations or
  identifiers unless marked `privacy: .private`.

---

## 6. Testing

Uses [Swift Testing][swift-testing] (`import Testing`, `@Test`, `#expect`,
`#require`). XCTest is only for UI and performance tests.

- **Every layer has its own test target**: `DomainTests`, `ApplicationTests`,
  `InfrastructureTests`, `PresentationTests`, plus `RoadSenseTests` for the
  composition root. `just test` runs them all.
- What to test where:
  - **Domain:** invariants and business rules. Pure and fast, with no fakes needed.
  - **Application:** use-case logic with **stub/fake ports** written in the test file.
  - **Infrastructure:** implementations against real but local resources
    (in-memory SwiftData container, `URLProtocol` stubs). No real network.
  - **Presentation:** view-model state transitions, with use cases backed by fake
    ports. Don't unit-test SwiftUI layout. Use previews and screenshots instead.
- Name tests with raw identifiers describing behavior:
  `` @Test func `rejects negative distance`() ``. SwiftFormat enforces this.
- Use parameterized tests (`@Test(arguments:)`) instead of copy-pasted cases.
- Structure tests as arrange / act / assert, separated by blank lines.
- Use `#require` to unwrap preconditions, and `#expect(throws:)` for errors.
- Tests **MUST** be deterministic. Inject clocks, UUIDs, and randomness instead of
  depending on `Date.now`, ordering, or timing.
- New features **MUST** come with tests, and bug fixes **SHOULD** come with a
  regression test.

---

## 7. Accessibility and HIG

From the Human Interface Guidelines: [Accessibility][hig-accessibility]. An
accessible interface is intuitive, perceivable, and adaptable.

- **MUST** support Dynamic Type. Use text styles (`.font(.headline)`) rather than
  fixed point sizes, and check layouts at the largest accessibility sizes.
- **MUST** give every meaningful image and icon-only button an accessibility label
  (`Label("Start", systemImage: "play.fill")` or `.accessibilityLabel`). Mark
  decorative images `.accessibilityHidden(true)`.
- Combine related elements so VoiceOver reads them as one item
  (`.accessibilityElement(children: .combine)`, as in `TripRow`).
- **MUST NOT** convey information by color alone. Add a shape, icon, or text.
- Prefer system colors. They adapt to Dark Mode and Increase Contrast. Check
  contrast in light and dark appearances.
- Respect **Reduce Motion** (`@Environment(\.accessibilityReduceMotion)`). Swap
  movement for fades and avoid auto-repeating animation.
- Hit targets **SHOULD** be at least 44×44 pt.
- Prefer standard controls and system gestures over custom ones. **AVOID**
  auto-dismissing UI on a timer.
- **Driving context:** this app may be used around vehicles. Keep interactions
  glanceable, with large targets, minimal text entry, and no flows that require
  attention while moving.

---

## 8. Privacy and permissions

From [Requesting authorization to use location services][location-auth] and
[Privacy manifest files][privacy-manifest].

- Ask for permission **in context**, right before the feature needs it, never at
  launch.
- Request the **minimum access level**: prefer *When In Use* location over
  *Always*. You can request Always only once, so make it count.
- Every permission needs a usage description, set as an `INFOPLIST_KEY_*` build
  setting (e.g. `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription`) on the app
  target for **both** Debug and Release. Authorization requests fail immediately
  if the key is missing.
- Handle every authorization state (`notDetermined`, `denied`, `restricted`,
  authorized) and changes while the app runs. A denied permission is a normal
  state with its own UI, not an error.
- Permission and authorization logic lives in **Infrastructure** behind a port.
  Presentation sees only a domain-level status.
- Add `RoadSense/Resources/PrivacyInfo.xcprivacy` as soon as the app collects data
  or uses a *required reason API* (e.g. `UserDefaults`, file timestamps, system
  boot time). Keep it updated.
- Store secrets and tokens in the Keychain, never in `UserDefaults` or source code.

---

## 9. Documentation comments

From the [API Design Guidelines][api-guidelines]: if an API is hard to describe
simply, the design may be wrong.

- **MUST** add a `///` doc comment to every `public` declaration, and **SHOULD**
  add one to non-obvious internal ones.
- Start with a one-line summary sentence fragment ending in a period. Functions
  say what they *do* and *return*. Types and properties say what they *are*.
- Add `- Parameter`, `- Returns`, `- Throws` only when they add information.
- Comments explain *why*, not *what*. Delete commented-out code.

---

## 10. Checklist before finishing

- [ ] Code is in the right layer, and no new `Package.swift` dependency was added to work around a layering error.
- [ ] Domain and Application import only `Foundation`.
- [ ] New infrastructure is behind a port and wired in `AppContainer` only.
- [ ] `@Observable` + `@State`/`@Environment`/`@Bindable` used. No `ObservableObject`.
- [ ] Zero compiler warnings. No `@unchecked Sendable` or `nonisolated(unsafe)` without justification.
- [ ] Tests added in each layer touched.
- [ ] Screen-level views have previews, labels, and Dynamic Type support.
- [ ] Permissions have usage strings and handle denial.
- [ ] `just check` passes. For UI changes, `just run` + `just screenshot` was checked.

---

## 11. Sources

- [Swift API Design Guidelines][api-guidelines] (swift.org)
- [Managing model data in your app][model-data] (Apple)
- [Migrating from ObservableObject to the Observable macro][observable-migration] (Apple)
- [Adopting strict concurrency in Swift 6 apps][swift6] (Apple)
- [Swift 6 migration guide][migration-guide] (swift.org)
- [SE-0466: Control default actor isolation inference][se-0466]
- [SE-0461: Run nonisolated async functions on the caller's actor by default][se-0461]
- [Organizing your code with local packages][local-packages] (Apple)
- [Swift Testing][swift-testing] (Apple)
- [Human Interface Guidelines: Accessibility][hig-accessibility] (Apple)
- [Requesting authorization to use location services][location-auth] (Apple)
- [Privacy manifest files][privacy-manifest] (Apple)

[api-guidelines]: https://www.swift.org/documentation/api-design-guidelines/
[model-data]: https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app
[observable-migration]: https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro
[swift6]: https://developer.apple.com/documentation/swift/adoptingswift6
[migration-guide]: https://www.swift.org/migration/documentation/migrationguide/
[se-0466]: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md
[se-0461]: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md
[local-packages]: https://developer.apple.com/documentation/xcode/organizing-your-code-with-local-packages
[swift-testing]: https://developer.apple.com/documentation/testing
[hig-accessibility]: https://developer.apple.com/design/human-interface-guidelines/accessibility
[location-auth]: https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services
[privacy-manifest]: https://developer.apple.com/documentation/bundleresources/privacy-manifest-files
