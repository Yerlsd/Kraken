# Kraken — Complete Implementation Blueprint

> Read-only architecture snapshot of branch engine3/wine11 at repository head 9f9cba4cda6b8d718de076a3f21e45f4f9cb8a70. This document is a plan only. No implementation is represented as complete by this document.

## Executive Summary

**CONFIRMED:** Kraken is a native macOS Swift/SwiftUI launcher whose current code combines a mature Mythic/Engine-2 path with an Engine-3/Wine-11 path. The core launch path is Game -> LaunchProfile -> RuntimeResolver -> GraphicsBackendResolver -> Wine container/runtime -> Foundation Process -> Windows executable -> GameOperation/process termination.

**CONFIRMED:** Only two runtime IDs exist in source today: mythic-engine and wine-11. GPTK 4 is not a first-class runtime implementation.

**CONFIRMED:** GraphicsBackend already separates Automatic, D3DMetal, DXMT, DXVK and WineD3D, but detection is still partly filesystem-presence based and Wine-11 DXVK detection is deliberately disabled.

**CONFIRMED:** Reported GPU Memory does not exist in the current source model. It must be designed as a compatibility/reporting policy, not physical VRAM allocation.

**CONFIRMED:** Steam is not implemented as a provider. SteamGame is a deprecated placeholder.

**CONFIRMED:** Epic is implemented through Legendary and is a hard regression constraint. The correct strategy is to wrap and preserve it, not rewrite it while adding Steam.

**CONFIRMED:** Current Wine.Container.Settings defaults are retinaMode=true and scaling=192. Project handoff identifies a known-good Wine-11 environment using retinaMode=false and 96 DPI.

**CONFIRMED:** The four test files contain 51 XCTest methods: GraphicsBackendTests 15, LaunchProfileMergeTests 12, PersistenceTests 8, RuntimeResolverTests 16. The handoff's 50-test statement is therefore historical/stale relative to this source snapshot.

**CONFIRMED:** The Xcode project includes test Swift files in Sources and also includes at least LaunchProfileMergeTests.swift, PersistenceTests.swift and RuntimeResolverTests.swift in Resources, matching the documented Copy Bundle Resources warning.

**HISTORICAL:** docs/DEVELOPMENT_HANDOFF.md records a previously verified Wine-11 environment, a working W11 container, a 50/50 passing suite, and a known-good Wine 11 + DXVK 1.10.3 Async + MoltenVK 1.4.1 Subnautica baseline. This blueprint does not treat those as fresh runtime verification.

**UNKNOWN:** The exact current runtime binary contents, MoltenVK/DXVK checksums, GPTK payload contents, and current real-game behavior cannot be established from the Swift repository alone.

The safest end state is not a larger Game/Wine god-object. It is a set of explicit boundaries:

    Game
      -> GameSource / GameInstallation
      -> CompatibilityProfile
      -> RuntimeRegistry / RuntimeProvider
      -> BackendRegistry / GraphicsBackendProvider
      -> HardwareCapabilities
      -> immutable LaunchPlan
      -> LaunchSession / ProcessMonitor
      -> DiagnosticSession

---

## Current Repository Reality

### Inventory

**CONFIRMED:** Repository tree contains 375 entries, including:
- Kraken.xcodeproj
- Kraken application target
- KrakenTests target
- 117 Swift source files
- 4 XCTest source files
- Assets.xcassets and multiple app icon resources
- bundled Legendary CLI/Python payload
- runtime/Wine code
- game/provider code
- UI/navigation/settings/import/install code
- CI workflows
- extensive project documentation.

### Major source map

| Area | Current source |
|---|---|
| App lifecycle | Mythic/KrakenApp.swift, Mythic/AppDelegate.swift |
| Game domain | Mythic/Utilities/Game/*.swift |
| Library/persistence | Mythic/Utilities/GameDataStore.swift, Persistence, Migrator |
| Runtime | Runtime.swift, Launch/RuntimeResolver.swift, Engine/* |
| Wine | Wine/WineInterface*.swift |
| Graphics | GraphicsBackend.swift, GraphicsBackendDetector.swift, GraphicsBackendResolver.swift |
| Launch | GameManager/*, GameOperation/* |
| Epic | EpicGamesGame.swift, EpicGamesGameManager.swift, Legendary/* |
| Steam | SteamGame.swift only; no functional manager/provider |
| UI | Views/Navigation, Views/Unified |
| Import/install | GameImportView and GameInstallationView |
| CI | .github/workflows/build.yml, swiftlint.yml |
| Project | Kraken.xcodeproj/project.pbxproj |
| Documentation | docs/*.md |

### Document/source discrepancies

**HISTORICAL:** The handoff describes a modified local working tree and an earlier HEAD/state.

**CONFIRMED CURRENT:** The GitHub branch currently points at 9f9cba4cda6b8d718de076a3f21e45f4f9cb8a70. The current source therefore takes precedence over the handoff when they disagree.

**CONFIRMED CURRENT:** Current test method count is 51, not 50.

**CONFIRMED CURRENT:** The source still contains the Wine-11 DXVK detector TODO that returns false.

**UNKNOWN:** GitHub APIs do not expose a developer's separate local uncommitted state. Repository history and local working-tree state must be treated as different facts.

---

## Current Architecture

### Actual launch flow

    UI
      -> GameDataStore Game
      -> Game.launchProfile
      -> RuntimeResolver.resolve(profile)
      -> runtime installation validation
      -> container validation
      -> container/runtime match
      -> GraphicsBackendResolver.resolve(...)
      -> environment construction
      -> Process configuration
      -> Wine runtime
      -> Windows executable
      -> GameOperation/process monitoring
      -> termination

**CONFIRMED:** RuntimeResolver returns a ResolvedLaunchTarget containing runtime, container, environment, launch arguments and resolved graphics backend.

**CONFIRMED:** RuntimeResolver does not silently replace a missing runtime/container or explicit unavailable backend.

**CONFIRMED:** LocalGameManager uses RuntimeResolver for Windows local games.

**CONFIRMED:** Legendary launch also resolves the same runtime/backend path.

**RISK:** Launch success is inferred primarily from process execution/termination. Process.run() returning is not proof that a game reached a usable window, rendered correctly, or initialized audio.

### Ownership problems

1. **Game is a mutable reference type stored in Set<Game>.** **CONFIRMED.**
2. **GameDataStore persistence is coupled to observation and Set remove/reinsert.** **CONFIRMED.**
3. **GameSettingsView contains domain reconciliation logic.** **CONFIRMED.**
4. **Runtime paths are hard-coded inside Engine/Wine helpers.** **CONFIRMED.**
5. **Container settings combine runtime, backend, display and performance concerns.** **CONFIRMED.**
6. **Provider semantics are represented by subclasses/managers instead of a provider abstraction.** **CONFIRMED.**
7. **Process lifecycle has no structured launch state machine.** **CONFIRMED.**
8. **Diagnostics are scattered across Logger/error strings rather than a launch diagnostic object.** **CONFIRMED.**

---

## Architecture Problems

### 1. Runtime extensibility

**ISSUE:** RuntimeID is an enum with only Mythic Engine and Wine 11.

**WHY:** The current Engine 3 implementation was added incrementally around the existing Engine 2 architecture.

**CONSEQUENCE:** GPTK and future Wine versions require switches and path logic throughout the core.

**SEVERITY:** Critical.

**FIX:** RuntimeDescriptor + RuntimeProvider + RuntimeRegistry. Runtime ID remains stable while executable/layout/version become data owned by the descriptor.

**VERIFY:** Engine 2 and Wine 11 resolve through the same interface while using completely separate binaries.

### 2. GPTK absent as a runtime

**ISSUE:** No GPTK RuntimeID/provider exists.

**CONSEQUENCE:** D3DMetal can only be detected as a possible Wine-11 component, which risks conflating GPTK's ABI with Wine 11.

**SEVERITY:** Critical.

**FIX:** GPTK gets its own runtime bundle, health checker, loader relationship, D3DMetal provider and manifest.

### 3. Graphics detection is not health validation

**ISSUE:** D3DMetal and DXMT are detected by path existence. Wine-11 DXVK detection checks for a path but returns false.

**CONSEQUENCE:** A present but corrupted or wrong-version component can be presented as usable.

**FIX:** Artifact manifests, checksums, architecture checks, binary metadata checks and runtime compatibility checks.

### 4. DXVK ownership is Engine-2-specific

**ISSUE:** Wine.DXVK.install copies DLLs from Engine.directory/DXVK and rejects non-Mythic containers.

**CONSEQUENCE:** Adding Wine-11 DXVK requires a new ownership model rather than extending this method.

**FIX:** Backend artifact installer owned by the runtime/backend registry.

### 5. Container settings are overloaded

**ISSUE:** Settings include Retina, scaling, DXVK, DXVK Async, Metal HUD, Windows version, MSync and AVX2.

**CONSEQUENCE:** Runtime-specific and backend-specific policy leaks into a generic container object.

**FIX:** Split ContainerIdentity, RuntimeBinding, DisplayPolicy, BackendPolicy and DiagnosticsPolicy.

### 6. Runtime selection/UI state

**HISTORICAL:** The handoff attributes persistence failure to constant Game bindings; investigation documentation also discusses computed Picker Binding identity and task timing.

**CONFIRMED:** The architecture remains binding-heavy and Game is a reference object in a Set.

**FIX:** Expose explicit store commands for compatibility mutations. UI should render canonical state and dispatch intent; view lifecycle must never silently rewrite persisted runtime/container choices.

### 7. Persistence coupling

**ISSUE:** GameDataStore observes mutable Game objects and persists on observation.

**CONSEQUENCE:** Multi-property compatibility edits can produce intermediate states and make mutation semantics dependent on SwiftUI observation.

**FIX:** Transactional repository commands with one persisted commit per user operation.

### 8. Process lifecycle

**ISSUE:** Foundation Process is treated as the primary launch-state signal.

**CONSEQUENCE:** Runtime startup, executable startup, game running, crash and clean exit are not distinct domain states.

**FIX:** LaunchSession state machine.

### 9. Provider architecture

**ISSUE:** Local/Epic use concrete Game subclasses and manager casts.

**CONSEQUENCE:** Steam would cause additional storefront branching throughout the core.

**FIX:** GameSource/GameInstallation/ProviderAdapter.

### 10. Apple Silicon policy

**ISSUE:** No HardwareCapabilities abstraction exists.

**CONSEQUENCE:** Automatic runtime/backend/VRAM/display decisions cannot be systematically hardware-aware.

**FIX:** HardwareCapabilities service.

---

## Swift / SwiftUI Audit

### Game

**CONFIRMED:** Game is @Observable, Codable, Identifiable and mutable. It owns launchProfile, installation state, favorites and lastLaunched.

**RISK:** Mutable reference semantics plus Set storage require explicit persistence triggering.

**RECOMMENDED:** Move toward immutable persisted records plus a MainActor store/editor.

### GameDataStore

**CONFIRMED:** @Observable @MainActor. It has resilient decoding, corruption detection, backup of unreadable payloads and suspended persistence.

**GOOD:** This is a solid base for migration safety.

**RISK:** It still exposes mutable Game objects and a Binding helper.

**RECOMMENDED:** Add command APIs while retaining the existing binding helper as a temporary compatibility layer.

### LaunchProfile

**CONFIRMED:** It contains defaultRuntimeID, runtimeOverride, container, launchArguments, graphicsBackend and lastSuccessfulBackend.

**GOOD:** Runtime override semantics are explicit and old payloads decode.

**RISK:** It is becoming the compatibility catch-all.

**RECOMMENDED:** Replace it over time with CompatibilityProfile plus policy objects.

### MainActor/Task/Sendable

**CONFIRMED:** GameOperation is @unchecked Sendable; LocalGameManager wraps Process in an @unchecked Sendable ProcessBox; several UI flows spawn Tasks.

**RISK:** These are necessary escape hatches today but can become correctness boundaries that are not enforced by the compiler.

**RECOMMENDED:** ProcessRunner actor/service owns Process instances. GameOperation receives immutable events/results.

### View lifecycle

**CONFIRMED:** GameSettingsView uses task-based container compatibility/status work.

**RISK:** A view lifecycle event can mutate game configuration.

**RECOMMENDED:** View tasks should load/observe only. Compatibility reconciliation belongs in a command/service layer.

### Deprecated global state

**CONFIRMED:** VariableManager is deprecated but remains globally accessible and @unchecked Sendable.

**RECOMMENDED:** Remove new usages, migrate existing settings/operation state to typed models, then delete after compatibility window.

---

## Game Model

### Current fields

**CONFIRMED:**
- id
- title
- installationState
- storefront
- launchProfile
- favorite state
- lastLaunched
- image URLs
- subclass-specific metadata.

### Future model

**RECOMMENDED:**

    GameRecord
      identity
      title/metadata
      sourceID
      installationIDs
      compatibilityProfileID
      favorite
      lastLaunched

    GameInstallation
      installationID
      location
      executable
      platform
      installationState
      providerIdentity

    GameSource
      providerID
      providerIdentity
      account
      capabilities

    CompatibilityProfile
      runtimePolicy
      containerPolicy
      graphicsPolicy
      reportedGPUMemoryPolicy
      displayPolicy
      launchArguments
      advancedCompatibility

Provider metadata must not be stored in the compatibility model.

---

## LaunchProfile

**CURRENT:** Value type, Codable/Equatable/Sendable.

**RECOMMENDED future fields/policies:**
- runtime automatic/explicit
- container automatic/explicit
- graphics automatic/explicit
- reported GPU memory automatic/manual
- display/scaling policy
- launch arguments
- advanced compatibility flags
- optional compatibility notes.

### Ownership

| Setting | Global | Per-game | Runtime-specific | Backend-specific |
|---|---|---|---|---|
| Runtime | yes | yes | n/a | no |
| Container | yes | yes | yes | no |
| Graphics | yes | yes | yes | yes |
| Reported GPU memory | yes | yes | yes | yes |
| Launch arguments | yes/optional | yes | no | no |
| Retina/scaling | yes | yes | yes | yes |
| Windows version | yes | yes | yes | no |
| DXVK async | advanced | yes | yes | DXVK |
| Metal HUD | advanced | yes | no | D3DMetal |

Persist intent. Resolve transient values at launch.

---

## Persistence

**CONFIRMED:** UserDefaults + property-list encoding is the current persistence layer. Migrator already has versioned historical migrations.

**RECOMMENDED migration sequence:**
1. Add explicit library schema version.
2. Preserve current LaunchProfile decoding.
3. Introduce CompatibilityProfile with compatibility decoder.
4. Introduce GameSource/GameInstallation.
5. Introduce stable ContainerID while retaining URL compatibility.
6. Add reported GPU memory policy.
7. Add runtime/backend artifact manifests.
8. Add diagnostic history.
9. Remove legacy fields only after migration coverage is complete.

Never delete malformed payloads automatically. Keep the existing backup/recovery philosophy.

---

## Runtime Architecture

### Current runtime model

**CONFIRMED:** Engine.wineRuntime(for:) directly maps RuntimeID to filesystem paths.

**CONFIRMED:** Wine 11 receives explicit loader environment variables.

**RECOMMENDED:**

    RuntimeDescriptor
      id
      family
      version
      architecture
      root
      executable
      wineserver
      capabilities
      supportedBackends
      manifest

    RuntimeProvider
      discover
      health
      createContainer
      buildEnvironment
      launch
      processList
      shutdown

Runtime-specific paths should be private to the provider.

### Isolation rule

No runtime may:
- borrow another runtime's wine executable
- borrow another runtime's wineserver
- inject another runtime's ntdll
- copy another runtime's D3DMetal/DXVK artifacts
- share mutable runtime installation directories.

Containers must carry runtime ownership.

---

## Mythic Engine

**CONFIRMED:** Engine 2 is rooted at Engine.directory and has legacy Wine/DXVK helpers.

**GOOD:** Wine.DXVK.install rejects non-Mythic containers.

**RECOMMENDED:** Wrap the existing implementation in Engine2RuntimeProvider without changing its binaries or directory layout. Add health checks and a golden real-game test.

Engine 2 is the compatibility anchor. It must not be refactored and upgraded simultaneously with Wine 11/GPTK work.

---

## Wine 11

**CONFIRMED:** Wine 11 is represented by a side-by-side Wine Stable.app under Runtimes/wine11.

**CONFIRMED:** Runtime installation checks wine, wineserver, wineboot, ntdll and wined3d.

**RISK:** Health checks do not yet validate complete binary provenance or all graphics components.

**RECOMMENDED:** RuntimeManifest with version, architecture, SHA-256, build provenance, loader relationship, graphics artifacts and schema version. Installation should be atomic and versioned.

---

## GPTK 4

**CONFIRMED:** No GPTK runtime exists in source.

**HISTORICAL:** Project documentation records GPTK 4 beta 2/D3DMetal 4.0b2 work and prior Wine Unix-call ABI mismatch, ntdll, Rosetta AOT/code-signature, runtime-mixing and D3DMetal environment failures.

**RECOMMENDED:** GPTK must be a separate runtime family with:
- its own Wine base
- its own loader/ntdll relationship
- its own D3DMetal framework
- its own manifest
- its own architecture/signature validation
- its own container ownership.

Never “make GPTK work” by adding GPTK components to Wine 11.

---

## Graphics Backends

**CONFIRMED:** GraphicsBackend models Automatic, D3DMetal, DXMT, DXVK and WineD3D.

**CONFIRMED:** Explicit backend choice throws if unavailable. Automatic considers last successful backend before ranked capability selection.

**RECOMMENDED:** Add BackendDescriptor with:
- backend ID
- owning runtime family
- API support
- artifact manifest
- hardware requirements
- health status
- game compatibility hints.

Automatic selection should filter candidates by runtime compatibility, hardware capabilities, artifact health and game history before ranking.

Explicit selection must never silently fall back.

---

## DXVK

**CONFIRMED:** Current installer is Engine-2-only and copies x64/x32 d3d10core.dll and d3d11.dll.

**CONFIRMED:** Wine-11 detector explicitly returns false after only checking d3d11.dll presence.

**RECOMMENDED:** Introduce GraphicsArtifactManifest:
- backend
- version
- source/provenance
- architecture
- SHA-256
- PE product/version metadata
- expected exports
- owning runtime.

Installation must validate before activation and retain the previous known-good artifact for rollback.

**HISTORICAL:** A bogus dxgi.dll incident is documented by project context. **UNKNOWN:** exact binary identity is not recoverable from source alone.

---

## MoltenVK / Metal

**CONFIRMED:** There is no first-class MoltenVK service in the Swift source tree.

**HISTORICAL:** MoltenVK 1.4.1 is identified by project context as part of the known-good Wine-11/DXVK baseline.

**RECOMMENDED:** Treat MoltenVK as a versioned runtime graphics artifact. Record loader/version/capabilities and validate Metal feature requirements before enabling DXVK.

---

## Subnautica Rendering Failure

**HISTORICAL:** Project context reports:
- Scanner physical model invisible while UI remains
- Gasopod body invisible while particles remain
- Lifepod geometry invisible
- static environment renders
- VK_ERROR_INITIALIZATION_FAILED
- signed integer vertex attribute rejected by Metal as unsigned.

**UNKNOWN:** Current repository does not contain the exact runtime error or prove the currently deployed binary path.

### Required investigation

Trace:

    Unity D3D11
      -> DXVK
      -> Vulkan/SPIR-V
      -> SPIRV-Cross/MSL
      -> MoltenVK
      -> Metal vertex descriptor

Capture the actual shader/input declaration and actual Vulkan attribute format. Determine where signedness changes.

### Fix decision

**RECOMMENDED:** Do not patch Subnautica assets.

- If DXVK emits incorrect Vulkan format: fix/update DXVK.
- If shader/resource type is lost during SPIR-V/MSL conversion: fix the translation layer.
- If MoltenVK maps a valid Vulkan format to an invalid Metal descriptor: fix/update MoltenVK.
- If the Metal descriptor is constructed incorrectly after valid Vulkan input: fix the Metal-facing mapping.

Before any change, create a minimal integer-vertex regression test. Validate skinned meshes, static meshes, instancing and multiple D3D11 games.

---

## GPU Memory / Reported VRAM

**CONFIRMED:** No current implementation.

**RECOMMENDED:**

    ReportedGPUMemoryPolicy
      automatic
      manual(megabytes)

Automatic must consider:
- unified memory capacity
- current memory pressure
- Apple GPU generation
- backend semantics
- compatibility evidence
- safe policy limits.

It must never mean “reserve this amount of physical memory.”

UI copy must explicitly say the value is reported to the Windows compatibility environment.

Tests must cover persistence, bounds, automatic resolution, backend-aware resolution and launch environment.

---

## Container Architecture

**CONFIRMED:** Wine.Container stores name, URL, UUID, settings and runtimeID. Settings currently combine display, runtime and backend concerns.

**CONFIRMED:** New settings defaults are retinaMode=true and scaling=192.

**HISTORICAL:** Known-good Wine-11 environment uses retinaMode=false and 96 DPI.

**RECOMMENDED:** Split:
- ContainerIdentity
- RuntimeBinding
- DisplayPolicy
- BackendPolicy
- PerformancePolicy
- DiagnosticsPolicy.

Default new Wine-11 containers to 1×/96 DPI unless a compatibility profile explicitly overrides it. Existing containers must not be blindly changed.

---

## Performance Architecture

**CONFIRMED:** Kraken uses many Tasks, image loading, storefront refresh, process polling, operations and UI observation.

**RECOMMENDED priorities:**
1. UI responsiveness.
2. stable frame pacing/launch responsiveness.
3. low background CPU.
4. bounded memory.
5. low launch overhead.
6. thermal/battery efficiency.
7. raw FPS.

Work:
- adaptive tasklist polling
- event-driven process notifications where possible
- pause nonessential refresh while games run
- lazy/bounded artwork cache
- deduplicate storefront refresh
- signpost launch phases
- measure memory/CPU of Kraken itself
- add sustained-session tests.

---

## Apple Silicon Strategy

**RECOMMENDED:** HardwareCapabilities should expose:
- CPU architecture/family
- GPU family
- unified memory capacity
- Metal feature capabilities
- Vulkan/MoltenVK capabilities
- Rosetta availability
- thermal class
- power state
- display scale.

Use these inputs for runtime/backend selection, reported GPU memory, display policy and background-work budgets. Do not hard-code a current Mac generation.

---

## Game Source Architecture

**CONFIRMED:** Current provider model uses LocalGame, EpicGamesGame, SteamGame and corresponding managers, with concrete type casts.

**RECOMMENDED:**

    GameSource
      providerID
      identity
      capabilities

    GameInstallation
      path
      executable
      platform
      provider identity
      installation state

    ProviderAdapter
      discover
      import
      install
      update
      verify
      uninstall
      launch
      metadata

This keeps Game provider-neutral.

---

## Steam

**CONFIRMED:** SteamGame is a deprecated placeholder. No functional Steam provider exists.

**RECOMMENDED implementation:**
1. Discover supported Steam library roots.
2. Parse AppID/install manifests.
3. Validate install paths.
4. Create provider identity.
5. Resolve executable.
6. Import into unified library.
7. Preserve Steam launch context where required.
8. Detect actual game process.
9. Cache metadata.
10. Add import/reconciliation tests.

Do not require users to browse Wine prefixes.

---

## Epic Games

**CONFIRMED:** Legendary is bundled and handles configuration, sign-in, install, update, repair, import, uninstall and launch.

**RECOMMENDED:** Preserve Legendary internally and expose it through EpicProviderAdapter. Add integration tests around the existing implementation instead of replacing it.

Regression matrix:
- discovery
- import
- install
- update
- repair
- launch
- offline mode
- runtime resolution
- container ownership
- process exit.

---

## Unified Library

### Proposed hierarchy

Primary:
- Library
- Operations
- Settings

Library:
- Continue Playing
- Favorites
- All Games
- Recently Added
- Needs Attention
- Search/filter.

Game detail:
- artwork
- title/source
- primary Play/Install/Repair
- concise compatibility summary
- Advanced Compatibility
- Files
- Diagnostics.

Containers become an advanced management surface rather than the main product concept.

---

## Installation / Import

**CONFIRMED:** Local and Epic import/install flows exist.

**RECOMMENDED unified flow:**

    Add Game
      -> source
      -> discover installation
      -> identify executable/platform
      -> create/reuse compatible container
      -> create compatibility profile
      -> validate
      -> library entry.

The user should never need to manually locate a WINEPREFIX for ordinary operation.

---

## Diagnostics

**RECOMMENDED structured LaunchDiagnostic:**

    gameID
    source
    installation
    runtime ID/version
    container
    backend/version
    reported GPU memory
    executable
    arguments
    environment summary
    launch phases
    failure category
    process exit
    timestamps.

Expose a human summary first, technical details second, and exportable diagnostics third.

---

## Error Handling

**CONFIRMED:** RuntimeResolver already has typed errors and recovery suggestions.

**RECOMMENDED:** Extend this pattern into a shared error taxonomy:
- provider
- installation
- runtime
- container
- graphics
- executable
- process
- permission
- compatibility.

Every error must answer:
1. What happened?
2. Why?
3. What Kraken can do.
4. What the user can do.

Avoid leaking concrete-type cast failures such as CocoaError coderInvalidValue into normal user flows.

---

## UI / UX Overhaul

### Product surface

The user should immediately understand:
- Play
- Install
- Add Game
- Settings
- Running/Stopped/Failed.

Normal users should not need to understand Wine, DXVK, MoltenVK, Vulkan, D3DMetal, DLL overrides, WINEPREFIX or registry keys.

### Game settings

Basic:
- launch arguments
- installation
- compatibility mode

Compatibility:
- Runtime
- Graphics
- Reported GPU Memory
- Container

Display:
- resolution
- scaling
- Retina

Advanced:
- DXVK async
- MSync
- AVX
- backend-specific options.

Diagnostics:
- resolved runtime
- resolved backend
- container health
- last launch
- export.

### State ownership

Views should hold only transient UI state. Canonical compatibility state belongs to GameDataStore/CompatibilityRepository. Changes are explicit commands.

---

## Testing Strategy

### Current suite

**CONFIRMED:** 51 test methods across four files:
- GraphicsBackendTests: 15
- LaunchProfileMergeTests: 12
- PersistenceTests: 8
- RuntimeResolverTests: 16.

### Missing coverage

Critical missing layers:
- runtime artifact health
- container creation/migration
- GPTK
- Steam
- Epic end-to-end
- process lifecycle
- diagnostics
- GPU memory policy
- hardware capabilities
- real graphics rendering
- long-session performance.

### Required test matrix

Unit:
- policy resolution
- migration
- backend selection
- runtime selection
- artifact validation.

Integration:
- GameDataStore + persistence
- provider import
- launch-plan construction
- process monitor.

Runtime:
- actual runtime executable
- container/runtime match
- backend initialization.

Real game:
- Engine 2 known-good
- Wine 11 known-good
- Subnautica rendering
- Epic title
- Steam title
- GPTK title.

Performance:
- idle CPU/memory
- launch latency
- sustained thermals
- frame pacing
- long-session stability.

---

## Build / CI / Packaging

**CONFIRMED:** Xcode project has Kraken and KrakenTests targets. CI runs xcodebuild build/test and a separate SwiftLint workflow.

**CONFIRMED:** Test Swift files are included in Resources as well as Sources for the test target, producing the documented Copy Bundle Resources warning.

**RECOMMENDED:** Remove test-source resource membership and add CI validation that no test source is packaged into Kraken.app.

CI should additionally:
- build Debug and Release
- run all tests
- run SwiftLint
- validate runtime manifests
- validate binary architectures
- validate no cross-runtime files
- validate migration fixtures.

---

## Binary / Dependency Management

**RECOMMENDED manifest fields:**
- artifact ID
- version
- upstream source
- source commit
- SHA-256
- architecture
- owning runtime
- owning backend
- install path
- dependencies
- signature/provenance.

Activation should be versioned and atomic. Keep the previous known-good version for rollback.

---

## Security / Safety

Realistic risks:
- arbitrary local game executable
- malicious imported metadata
- path traversal
- environment injection
- corrupted downloaded runtime
- substituted DLL/framework.

Mitigations:
- Process executableURL + argument arrays, not shell strings
- canonicalize and validate paths
- checksum downloaded artifacts
- verify architecture/signatures
- never execute files during discovery
- sanitize diagnostics
- isolate runtime install destinations
- require confirmation for destructive operations.

---

## Migration Strategy

1. Add schema version.
2. Preserve old LaunchProfile decoding.
3. Migrate to CompatibilityProfile.
4. Introduce source/install identities.
5. Add stable container identity.
6. Add runtime/backend manifests.
7. Add reported GPU memory.
8. Add diagnostics history.
9. Retire legacy fields only after fixture coverage.

Migration must always preserve the old payload until the new payload validates.

---

## Implementation Roadmap

### Phase 0 — Baseline protection
Goal: freeze Engine 2/Wine 11 known-good behavior as tests and manifests.
Dependencies: none.
Verification: real-game smoke tests.
Rollback: no runtime mutation.

### Phase 1 — Domain foundation
Create RuntimeDescriptor, RuntimeProvider, BackendDescriptor, BackendProvider, GameSource, GameInstallation, CompatibilityProfile, LaunchPlan and LaunchDiagnostic.
Modify Game, Runtime, GraphicsBackend, GameDataStore, RuntimeResolver.
Risk: persistence shape.
Verification: old payloads still decode.

### Phase 2 — Persistence
Add schema version and migrations.
Modify Migrator/GameDataStore/Game/LaunchProfile compatibility.
Verification: legacy fixtures and corruption recovery.

### Phase 3 — Runtime isolation
Create Engine2Provider and Wine11Provider.
Modify Engine/Runtime/Wine/RuntimeResolver.
Verification: each launch uses only its own runtime.

### Phase 4 — Graphics isolation
Create artifact manifests and backend providers.
Modify graphics detector/resolver and DXVK handling.
Verification: corrupted/wrong artifacts fail before launch.

### Phase 5 — Container model
Split container identity/runtime/display/backend policies.
Modify Wine container code and container UI.
Verification: 1×/96 new-container policy; deliberate existing settings preserved.

### Phase 6 — Provider abstraction
Wrap Local and Epic without changing user behavior.
Verification: Epic regression suite.

### Phase 7 — Steam
Implement discovery/import/launch/process adapter.
Verification: real installed Steam title.

### Phase 8 — GPU memory/hardware
Add HardwareCapabilities and ReportedGPUMemoryPolicy.
Verification: automatic/manual persistence and backend-aware resolution.

### Phase 9 — GPTK
Implement isolated runtime bundle and D3DMetal provider.
Verification: health check + real game.

### Phase 10 — Subnautica rendering
Reproduce, isolate signedness failure, then change the responsible translation layer.
Verification: skinned/static regression matrix.

### Phase 11 — Process/diagnostics
Add LaunchSession, ProcessMonitor and DiagnosticSession.
Verification: startup/crash/exit/error state accuracy.

### Phase 12 — Performance
Reduce background work and add instrumentation.
Verification: sustained Apple Silicon sessions.

### Phase 13 — UI overhaul
Rebuild Library/Game Detail/Settings around stable domain APIs.
Verification: accessibility, persistence and responsiveness.

### Phase 14 — Final validation
Full unit, integration, runtime, provider, graphics and real-game matrix.

---

## Exact File-Level Change Plan

### Mythic/Utilities/Game/Game.swift
**CURRENT:** Game and LaunchProfile own most mutable compatibility state.  
**PROBLEM:** domain, persistence compatibility and resolver policy are coupled.  
**PROPOSED:** CompatibilityProfile with backward decoder; retain LaunchProfile compatibility wrapper during migration.  
**TEST:** migration, equality, override semantics.  
**RISK:** persisted-data compatibility.

### Mythic/Utilities/Game/Runtime.swift
**CURRENT:** enum + hard-coded filesystem mapping.  
**PROBLEM:** cannot scale to GPTK/future Wine.  
**PROPOSED:** runtime registry/provider descriptors.  
**TEST:** discovery, health, runtime isolation.

### Mythic/Utilities/Launch/RuntimeResolver.swift
**CURRENT:** validates profile and creates ResolvedLaunchTarget.  
**PROBLEM:** knows Engine/Wine implementation details.  
**PROPOSED:** resolve through runtime/backend providers into immutable LaunchPlan.  
**TEST:** deterministic resolution and explicit failures.

### Mythic/Utilities/Game/GraphicsBackendDetector.swift
**CURRENT:** path-based detection; Wine 11 DXVK hard-disabled.  
**PROBLEM:** presence is not integrity.  
**PROPOSED:** artifact manifest + health checker.  
**TEST:** valid/invalid binaries.

### Mythic/Utilities/Game/GraphicsBackendResolver.swift
**CURRENT:** explicit -> last success -> ranked -> WineD3D.  
**PROBLEM:** ranking lacks hardware/game compatibility evidence.  
**PROPOSED:** capability graph and health-aware policy.  
**TEST:** deterministic selection.

### Mythic/Utilities/GameDataStore.swift
**CURRENT:** MainActor observable library and UserDefaults persistence.  
**PROBLEM:** persistence depends on mutable reference observation.  
**PROPOSED:** explicit mutation transactions and repository boundary.  
**TEST:** atomic profile edits and migration.

### Mythic/Utilities/Wine/WineInterface.swift
**CURRENT:** legacy Engine-2 and runtime-aware helpers coexist.  
**PROBLEM:** two abstractions for Wine execution.  
**PROPOSED:** runtime providers own runtime-specific Wine operations.  
**TEST:** no cross-runtime execution.

### Mythic/Utilities/Wine/WineInterface+Container.swift
**CURRENT:** container owns mixed settings and auto-saves via property observers.  
**PROBLEM:** implicit persistence and overloaded settings.  
**PROPOSED:** explicit container service + split policy objects.  
**TEST:** migration/defaults/ownership.

### Mythic/Utilities/Wine/WineInterface+DXVK.swift
**CURRENT:** Engine-2 DLL replacement.  
**PROBLEM:** cannot safely support multiple runtimes.  
**PROPOSED:** versioned backend artifact installer.  
**TEST:** checksum, architecture and runtime ownership.

### Mythic/Utilities/GameManager/LocalGameManager.swift
**CURRENT:** Foundation Process + termination continuation.  
**PROBLEM:** no semantic launch-state model.  
**PROPOSED:** ProcessRunner + LaunchSession.  
**TEST:** cancellation/start failure/crash/clean exit.

### Mythic/Utilities/GameManager/Legendary/LegendaryInterface.swift
**CURRENT:** concrete Legendary CLI integration.  
**PROBLEM:** provider concerns are exposed to core.  
**PROPOSED:** keep implementation, wrap behind EpicProviderAdapter.  
**TEST:** full Epic regression.

### Mythic/Utilities/Game/SteamGame.swift
**CURRENT:** deprecated placeholder.  
**PROBLEM:** no Steam source.  
**PROPOSED:** provider-backed installation identity; preserve legacy decode if needed.  
**TEST:** AppID/import/launch.

### Mythic/Views/Unified/Sheets/GameSettingsView.swift
**CURRENT:** view contains runtime/container/backend editing and asynchronous reconciliation.  
**PROBLEM:** UI lifecycle can mutate canonical configuration.  
**PROPOSED:** intent-based compatibility editor.  
**TEST:** edit/persist/reopen/restart.

### Mythic/Views/Unified/Components/GameListView.swift
**CURRENT:** ID-based GameDataStore bindings.  
**PROPOSED:** immutable projections + command dispatch.  
**TEST:** no UI-local configuration divergence.

### Mythic/Views/Navigation/HomeView.swift
**CURRENT:** recent/favorites/container dashboard.  
**PROPOSED:** library-first information architecture.  
**TEST:** navigation and state restoration.

### Kraken.xcodeproj/project.pbxproj
**CURRENT:** test source files also appear in Resources.  
**PROPOSED:** remove resource membership and enforce in CI.  
**TEST:** inspect built app bundle.

### KrakenTests/*.swift
**CURRENT:** 51 methods across four files.  
**PROPOSED:** add provider, runtime health, process, hardware, migration and real-runtime integration layers.  
**TEST:** target must execute every test.

### .github/workflows/build.yml
**CURRENT:** build/test CI.  
**PROPOSED:** artifact/schema/target-membership validation and explicit Debug/Release coverage.  
**TEST:** clean checkout CI.

---

## Risk Register

| ID | Risk | Likelihood | Impact | Mitigation | Detection | Rollback |
|---|---|---|---|---|---|---|
| R1 | Engine 2 regression | Medium | Critical | immutable runtime + smoke test | real game | disable new provider |
| R2 | Wine 11 regression | Medium | Critical | manifest + golden test | runtime health | retain known-good bundle |
| R3 | GPTK ABI mismatch | High | Critical | isolated provider + ABI checks | health test | disable GPTK |
| R4 | persistence migration loss | Medium | Critical | backup/version/fixtures | migration tests | restore old payload |
| R5 | graphics regression | High | Critical | artifact manifests + game matrix | rendering tests | activate prior backend |
| R6 | bogus DXVK component | Medium | Critical | checksum/provenance | artifact validator | previous artifact |
| R7 | MoltenVK regression | Medium | Critical | versioned stack | graphics smoke | previous stack |
| R8 | Swift concurrency race | Medium | High | actor boundaries | concurrency testing | revert subsystem |
| R9 | UI state drift | High | High | store commands | integration test | compatibility layer |
| R10 | Epic regression | Medium | Critical | adapter around Legendary | Epic smoke | preserve old adapter |
| R11 | Steam false import | Medium | High | manifest validation | fixture tests | disable provider |
| R12 | runtime/container mismatch | Medium | Critical | preflight | LaunchPlan validation | fail before process |
| R13 | hardware-specific tuning | Medium | High | capabilities | hardware matrix | generic defaults |
| R14 | false running state | High | High | LaunchSession | lifecycle tests | conservative state |
| R15 | runtime update corruption | Medium | Critical | atomic activation | manifest check | activate previous version |

---

## Failure Elimination Plan

### Missing skinned meshes
**HISTORICAL:** Metal rejects a signed integer vertex attribute where the descriptor is unsigned.  
**PLAN:** reproduce -> capture shader/input types -> capture Vulkan attribute -> identify translation boundary -> isolated fix -> multi-game regression.

### 128 MB reported GPU memory
**HISTORICAL:** project context identifies a low reported-memory issue.  
**PLAN:** trace actual reporting source, introduce explicit policy, remove implicit constants, validate backend-aware automatic resolution.

### Fresh containers use expensive Retina scaling
**CONFIRMED:** current defaults are Retina on and 192 DPI.  
**PLAN:** DisplayPolicy with 1×/96 generic default; migrate only uncustomized environments.

### Epic architecture is concrete
**CONFIRMED:** Legendary owns Epic semantics.  
**PLAN:** adapter boundary, not rewrite.

### Steam absent
**CONFIRMED:** placeholder only.  
**PLAN:** provider adapter + AppID/install discovery + launch context.

### Runtime selection drift
**CONFIRMED/HISTORICAL:** selection persistence has been a known bug.  
**PLAN:** explicit store commands + immutable LaunchPlan + no lifecycle mutation.

### GPTK ABI problems
**HISTORICAL:** known from project documentation/context.  
**PLAN:** isolated runtime and ABI health checks.

### DXVK packaging problems
**HISTORICAL:** bogus binary incident.  
**PLAN:** artifact manifest, checksum, provenance and atomic activation.

### UI too technical
**CONFIRMED:** Containers and Operations are prominent and compatibility controls expose implementation concepts.  
**PLAN:** Library/Game Detail first; progressive disclosure.

### Apple Silicon performance
**CONFIRMED:** no hardware policy abstraction.  
**PLAN:** HardwareCapabilities + background-work budget + sustained hardware validation.

---

## Mistakes to Avoid

- Do not patch ntdll casually.
- Do not mix GPTK into Wine 11.
- Do not identify binaries from filenames alone.
- Do not trust UI selection as proof of actual launch runtime.
- Do not equate FPS with compatibility.
- Do not equate build success with runtime success.
- Do not treat DXVK initialization as proof of correct rendering.
- Do not assume 128 MB explains every graphics failure.
- Do not randomly add MoltenVK flags.
- Do not blindly upgrade DXVK/MoltenVK.
- Do not use game-specific asset hacks for generic translation problems.
- Do not break Epic while adding Steam.
- Do not destroy the known-good Engine 2/Wine 11 baseline.
- Do not silently fall back from explicit runtime/backend choices.
- Do not let SwiftUI view tasks rewrite persisted compatibility.
- Do not use @unchecked Sendable as the concurrency architecture.
- Do not overwrite corrupt library data.
- Do not install runtime binaries without provenance/integrity validation.
- Do not equate physical unified memory with Windows VRAM.
- Do not expose raw WINEPREFIX/DXVK/registry configuration to normal users.
- Do not call a game “running” merely because Process.run() succeeded.
- Do not ship UI controls that imply unimplemented functionality.

---

## Definition of Done

### Runtime
- Mythic Engine genuinely launches a real Windows game.
- Wine 11 genuinely launches a real Windows game.
- GPTK 4 genuinely launches a real compatible Windows game.
- Diagnostics prove runtime executable/version.

### Graphics
- Correct meshes, shaders, textures and effects.
- Explicit backend respected.
- Automatic backend deterministic and health-checked.
- No silent rendering failures.
- Graphics artifacts have provenance/version/integrity.

### Audio
- Working and regression-free across the supported runtime matrix.

### Sources
- Manual
- Epic
- Steam

### Library
- Unified
- Searchable
- Favorites
- Recent/Continue Playing
- Clear install/running/failure state.

### Configuration
- Persistent
- Deterministic
- Runtime-aware
- Backend-aware
- Migration-safe.

### Performance
- Responsive UI
- bounded background work
- low unnecessary memory/CPU
- sensible thermals
- stable sustained gameplay.

### UI
- native macOS feel
- obvious Play
- progressive disclosure
- accessible
- responsive.

### Diagnostics
- accurate runtime/backend/container/executable reporting
- actionable errors
- exportable diagnostics.

---

## First 20 Actions

1. Freeze Engine 2 and Wine 11 runtime artifacts with manifests. Verify by real-game smoke tests. Rollback: no runtime mutation.
2. Create compatibility fixture snapshots for current persisted payloads.
3. Encode current runtime/backend/container launch behavior as integration contracts.
4. Introduce RuntimeDescriptor/RuntimeRegistry.
5. Introduce BackendDescriptor/BackendRegistry.
6. Define immutable LaunchPlan.
7. Define CompatibilityProfile ownership rules.
8. Add persistence schema version and migration fixtures.
9. Separate container identity from runtime ownership.
10. Add runtime health contracts.
11. Add graphics artifact manifests and provenance.
12. Wrap current Epic and Local implementations behind provider interfaces.
13. Implement Steam discovery/import adapter.
14. Add HardwareCapabilities.
15. Add ReportedGPUMemoryPolicy.
16. Add LaunchSession/ProcessMonitor.
17. Add structured LaunchDiagnostic.
18. Reproduce Subnautica vertex-format failure in a minimal harness.
19. Rebuild UI around Library/Game Detail/Advanced Compatibility.
20. Run the complete Apple Silicon real-game matrix, including sustained sessions.

---

## Unverified Items

1. **UNKNOWN:** Current runtime binaries were not executed in this read-only source analysis.
2. **UNKNOWN:** Exact current DXVK/MoltenVK binary versions/checksums.
3. **UNKNOWN:** Current Subnautica rendering reproduction.
4. **UNKNOWN:** Exact translation layer responsible for signedness divergence.
5. **UNKNOWN:** Current GPTK payload/ABI compatibility.
6. **UNKNOWN:** Current Steam client/library behavior on supported installations.
7. **UNKNOWN:** Current real-world Epic launch behavior on this snapshot.
8. **UNKNOWN:** Developer-local uncommitted working tree.
9. **UNKNOWN:** Current packaged runtime artifact integrity.
10. **UNKNOWN:** Exact historical bogus dxgi.dll artifact.
11. **UNKNOWN:** Cross-generation Apple Silicon thermal behavior.
12. **UNKNOWN:** Current live CI result as runtime proof.

---

## Final Engineering Position

Kraken should remain simple at the surface and explicit underneath.

The critical architectural rule is separation of concerns:

- Game describes the user's library item.
- Source describes where the game came from.
- Installation describes what is on disk.
- CompatibilityProfile describes user intent.
- RuntimeProvider owns one runtime family and its binaries.
- GraphicsBackendProvider owns one graphics translation stack.
- HardwareCapabilities describes the host.
- LaunchResolver combines those inputs into one immutable LaunchPlan.
- ProcessMonitor reports what actually happened.
- Diagnostics records the evidence.
- SwiftUI renders state and sends intent; it does not secretly repair compatibility state.

This gives Kraken the required path from a simple Play button to a technically rigorous native macOS Windows-game platform without turning every future runtime, backend or storefront into another branch of the existing Game class.
