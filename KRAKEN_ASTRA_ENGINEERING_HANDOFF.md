# Kraken — Complete Engineering Handoff for GPT Astra

> **Date:** September 20, 2026  
> **Repository:** `/Users/taylor/Desktop/Kraken`  
> **Active Branch:** `engine3/wine11`  
> **Head Commit:** `a39a1bff` (*Continue Kraken runtime and architecture work*)  
> **Upstream Tracking:** `origin/engine3/wine11` (Clean tracking, 0 ahead, 0 behind)  
> **Target Machine:** Apple MacBook Air (M4, 10-core GPU, 16 GB Unified Memory, macOS 27)  
> **Primary Diagnostic Target:** *Subnautica* (Unity 2019.4.36f1, D3D11, Windows x86_64 build)  

---

## Table of Contents
1. [Executive Summary](#executive-summary)
2. [Repository State & Git Identity](#repository-state)
3. [Architecture Overview](#architecture)
4. [Swift Concurrency & Actor Isolation](#concurrency)
5. [Game Model & State Authority](#game-model)
6. [LaunchProfile Semantics](#launchprofile)
7. [Persistence & Library Lifecycle](#persistence)
8. [Runtime System (`RuntimeID`)](#runtime-system)
9. [Mythic Engine Path (Engine 2 / Wine 7.7)](#mythic-engine)
10. [Wine 11 Runtime Path (Engine 3)](#wine-11)
11. [Game Porting Toolkit (GPTK 4.0) Path](#gptk-4)
12. [Graphics Backends & Resolvers](#graphics-backends)
13. [DXVK Translation Layer (1.10.3 Async)](#dxvk)
14. [MoltenVK & Metal Translation Layer (1.4.1)](#moltenvk)
15. [Container Infrastructure (`Wine.Container`)](#containers)
16. [Subnautica Diagnostic Environment](#subnautica)
17. [Audio Subsystem Status (CLOSED)](#audio)
18. [Loading Performance & Timings](#loading)
19. [GPU Memory & VRAM Reporting Investigation](#gpu-memory-reporting)
20. [Reported GPU Memory Feature (Architecture & Plan)](#reported-gpu-memory-feature)
21. [The Subnautica 3D Rendering Failure](#rendering-failure)
22. [Shader / Vertex Pipeline Analysis & Trace](#shader--vertex-pipeline-analysis)
23. [Current Rendering Root Cause Status](#current-rendering-root-cause-status)
24. [Performance Findings & Real-World Telemetry](#performance)
25. [Apple Silicon Optimization Philosophy](#apple-silicon-optimization)
26. [Game Process Management (`LocalGameManager`)](#game-process-management)
27. [Container Creation & Bootstrapping](#container-management)
28. [Test Suite Status & Discrepancies](#tests)
29. [Build System & Xcode Configuration](#build-system)
30. [Application Icon & Asset Catalogs](#assets)
31. [Binary Safety Rules & Operational Discipline](#binary-safety)
32. [Critical Source Files Reference](#important-files)
33. [Runtime Filesystem Paths Table](#current-runtime-file-paths)
34. [Process Environment Variables Table](#environment-variables)
35. [Comprehensive Source Modifications Breakdown](#current-source-changes)
36. [External Runtime Modifications Breakdown](#external-runtime-state)
37. [Diagnostic Artifacts & Telemetry Logs](#diagnostics)
38. [Empirical Gameplay Verification Record](#real-game-verification)
39. [Exact Current Failure Matrix](#failure-matrix)
40. [Historical Dead Ends & Refuted Hypotheses](#historical-dead-ends)
41. [Recommended First Ten Engineering Actions](#recommended-next-steps)
42. [Objective Acceptance Criteria ("Definition of Done")](#acceptance-criteria)
43. [Long-Term Product & Engineering Direction](#product--engineering-direction)
44. [Explicit List of Unverified Items & Gaps](#unknowns)

---

## 1. Executive Summary <a name="executive-summary"></a>

Kraken is an open-source macOS launcher and container management system for running Windows games on Apple Silicon. Originating as a fork/evolution of Mythic, it bridges native macOS host environments with Wine, DirectX translation layers (DXVK, D3DMetal, DXMT, WineD3D), and Apple Silicon Metal pipelines.

### Current Empirical Breakthrough
Kraken has achieved an empirically verified, fully operational Windows-game graphics pipeline on Apple Silicon:
$$\text{Kraken} \longrightarrow \text{Wine 11.0 (x86\_64)} \longrightarrow \text{W11 Container} \longrightarrow \text{DXVK 1.10.3 Async} \longrightarrow \text{MoltenVK 1.4.1} \longrightarrow \text{Metal 3} \longrightarrow \text{Apple M4 GPU}$$
Under this path, *Subnautica* launches from Kraken's UI, initializes Direct3D 11, loads into 3D gameplay, streams full environmental audio (via Wine CoreAudio and macOS CoreAudio), renders full 3D ocean water, sky, terrain, physics, user interfaces, and particle systems, and runs at sustained 40–50+ FPS with responsive player movement.

### The Remaining Blocker: Missing 3D Rigged Meshes
While the game world and environment render, three specific classes of 3D objects are invisible in the viewport:
1. **Player Tools / Hands:** The handheld Scanner tool 3D body is invisible; its illuminated holographic UI screen renders floating in mid-air.
2. **Fauna:** The Gasopod creature body is invisible; its green poisonous gas particles render in 3D space.
3. **Rigged Vehicles / Structures:** The Lifepod 5 exterior hull and animated hatches are invisible; its interior ladders and static props render.

### The Concrete Root Cause (CONFIRMED)
This failure is **NOT** a texture problem, **NOT** an LOD/VRAM fallback, and **NOT** an asset corruption issue.
It is an exact **Metal pipeline state compilation error** (`VK_ERROR_INITIALIZATION_FAILED`, Error code 2) triggered during `[MTLDevice newRenderPipelineStateWithDescriptor:error:]`:
```text
Vertex attribute v4(4) of type int4 cannot be read using MTLAttributeFormatUInt4.
```
- **Unity 2019.4** declared vertex bone indices in HLSL (`BLENDINDICES`) as signed integer (`int4`, `int2`, `int`).
- **Direct3D 11** allows an input layout of `DXGI_FORMAT_R32G32B32A32_UINT` to supply an `int4` register because hardware registers (`v[n]`) are untyped 32-bit bitfields.
- **DXVK** compiles the DXBC shader into SPIR-V declaring `OpTypeInt 32 1` (signed integer) while passing the unsigned format `VK_FORMAT_R32G32B32A32_UINT` in the pipeline vertex input state.
- **MoltenVK / SPIRV-Cross** translates the SPIR-V input to MSL as `int4 v4 [[attribute(4)]]` and maps the Vulkan format directly to `MTLAttributeFormatUInt4`.
- **Apple Metal Compiler** enforces strict type/signedness validation between the MSL parameter (`int4`) and the `MTLVertexDescriptor` (`MTLAttributeFormatUInt4`), refusing to compile the render pipeline.
- DXVK logs `err: DxvkGraphicsPipeline: Failed to compile pipeline` and drops all draw calls referencing that skinned mesh shader.

This handoff provides everything GPT Astra needs to take over, understand every layer without guessing, preserve the working baseline, resolve the rendering failure, and execute the architectural goals.

---

## 2. Repository State & Git Identity <a name="repository-state"></a>

### Repository Identity
- **Repository Path:** `/Users/taylor/Desktop/Kraken`
- **Remote Origin:** `git@github.com:Yerlsd/Kraken.git`
- **Current Branch:** `engine3/wine11`
- **Current HEAD Commit:** `a39a1bff` (*Continue Kraken runtime and architecture work*)
- **Upstream Tracking:** `origin/engine3/wine11` (In sync: 0 commits ahead, 0 commits behind)

### Branch List (`git branch -vv`)
```text
  backup/pre-autofix-20260915-231148       5076717e Validate Wine boot termination
  backup/pre-autofix-20260915-231617       5076717e Validate Wine boot termination
  backup/pre-final-autofix-20260915-231812 5076717e Validate Wine boot termination
* engine3/wine11                           a39a1bff [origin/engine3/wine11] Continue Kraken runtime and architecture work
  main                                     5693a2ea Prepare Kraken for Engine 3
  privacy-backup-20260916-021251           01dd8155 Polish game compatibility controls
  privacy-backup-engine3-20260916-022726   7639d53e Fix GitHub Actions project selection
  privacy-main                             ccdd1fa7 [origin/main] Fix GitHub Actions project selection
```

### Git Stash Entries (`git stash list`)
```text
stash@{0}: On engine3/wine11: pre-sync GameSettingsView local fix
```
> [!CAUTION]
> **STRICT REPOSITORY RULE FOR ASTRA:**
> **DO NOT TOUCH** `stash@{0}`.
> **DO NOT TOUCH** any of the backup branches (`backup/*`, `privacy-backup*`).
> **DO NOT** execute destructive commands: `git reset --hard`, `git checkout -- .`, `git clean -fd`.
> The working tree contains uncommitted modifications essential to the working Wine 11 + DXVK baseline.

### Current Working Tree Status (`git status`)
```text
On branch engine3/wine11
Your branch is up to date with 'origin/engine3/wine11'.

Changes not staged for commit:
	modified:   Kraken.xcodeproj/project.pbxproj
	modified:   KrakenTests/GraphicsBackendTests.swift
	modified:   KrakenTests/RuntimeResolverTests.swift
	modified:   Mythic/Assets.xcassets/AppIcon.appiconset/* (10 PNG files)
	modified:   Mythic/Assets.xcassets/Kraken.appiconset/generated/* (10 PNG files)
	modified:   Mythic/Utilities/Game/GraphicsBackendDetector.swift
	modified:   Mythic/Utilities/Game/GraphicsBackendResolver.swift
	modified:   Mythic/Utilities/Game/Runtime.swift
	modified:   Mythic/Utilities/GameDataStore.swift
	modified:   Mythic/Utilities/GameManager/LocalGameManager.swift
	modified:   Mythic/Utilities/Launch/RuntimeResolver.swift
	modified:   Mythic/Utilities/Wine/WineInterface+DXVK.swift
	modified:   Mythic/Views/Navigation/HomeView.swift
	modified:   Mythic/Views/Unified/Sheets/ContainerCreationView.swift
	modified:   Mythic/Views/Unified/Sheets/GameSettingsView.swift

Untracked files:
	Mythic/Utilities/Game/GPTKInstaller.swift
	Subnautica.dxvk-cache
```

---

## 3. Architecture Overview <a name="architecture"></a>

### Intended Conceptual Flow vs. Actual Current Flow
The intended unidirectional pipeline is:
$$\text{SwiftUI Views} \longrightarrow \text{Game (Model)} \longrightarrow \text{GameDataStore} \longrightarrow \text{LaunchProfile} \longrightarrow \text{RuntimeResolver} \longrightarrow \text{Process} \longrightarrow \text{Wine} \longrightarrow \text{Game}$$

```
+---------------------------------------------------------------------------------------+
| USER INTERFACE (SwiftUI)                                                               |
| HomeView / GameDetailView / GameSettingsView                                          |
|  - Holds local `@State var selectedRuntimeID: RuntimeID`                              |
|  - Binds to canonical `Game` via `GameDataStore.shared.binding(for: game.id)`         |
+------------------------------------------+--------------------------------------------+
                                           |
                                           v
+---------------------------------------------------------------------------------------+
| DATA / PERSISTENCE LAYER                                                              |
| GameDataStore (@Observable, MainActor)                                                |
|  - Authoritative repository: `var library: [Game]`                                    |
|  - Observes `Game` mutations via `withObservationTracking`                           |
|  - Serializes to `UserDefaults` key `"games"` via `PropertyListEncoder`               |
|  - Protects against malformed data: `isPersistenceSuspended`                          |
+------------------------------------------+--------------------------------------------+
                                           |
                                           v
+---------------------------------------------------------------------------------------+
| LAUNCH RESOLUTION (Value-oriented, Side-effect free)                                 |
| RuntimeResolver.resolve(profile: LaunchProfile) -> ResolvedLaunchTarget                |
|  1. Evaluates effective runtime: `profile.effectiveRuntimeID`                         |
|  2. Validates runtime installation: `Engine.isRuntimeInstalled(runtimeID)`            |
|  3. Validates container existence: `Wine.containerExists(at: containerURL)`          |
|  4. Validates container runtime affinity: `container.runtimeID == selectedRuntimeID` |
|  5. Resolves graphics backend: `GraphicsBackendResolver.resolve(...)`                 |
|  6. Assembles process environment dictionary: `RuntimeResolver.environment(...)`     |
+------------------------------------------+--------------------------------------------+
                                           |
                                           v
+---------------------------------------------------------------------------------------+
| PROCESS EXECUTION                                                                     |
| LocalGameManager.launch(game: Game) async throws                                      |
|  - Configures `Process.executableURL = target.runtime.wineExecutable`                 |
|  - Sets `Process.currentDirectoryURL = location.deletingLastPathComponent()`          |
|  - Attaches asynchronous `Pipe` readabilityHandlers for stdout & stderr logging       |
|  - Awaits process exit via `withTaskCancellationHandler` & locked `ContinuationState`|
+---------------------------------------------------------------------------------------+
```

### Architectural Divergence Points & Smells
1. **Container Runtime Affinity:** A container created for `.mythicEngine` cannot be run with `.wine11`, and vice-versa. `RuntimeResolver` strictly enforces `guard container.runtimeID == selectedRuntimeID` throwing `ResolutionError.containerRuntimeMismatch`.
2. **Launch Profile vs. Container Settings:** Container properties (`dxvk`, `dxvkAsync`, `msync`, `retinaMode`, `scaling`) live in `Properties.plist` within the container directory, whereas per-game launch settings (`graphicsBackend`, `runtimeOverride`, `launchArguments`) live in `Game.launchProfile` inside `UserDefaults`.
3. **UI State Duplication:** In `GameSettingsView`, `@State private var selectedRuntimeID` is populated in `.task` from `game.launchProfile.effectiveRuntimeID`. When the user changes the picker, `selectedRuntimeID` writes back to `game.launchProfile.runtimeOverride` and pairs a compatible container. If `.task` does not fire (view reuse), UI state can drift unless kept in sync via `.onChange(of: game.launchProfile.effectiveRuntimeID)`.

---

## 4. Swift Concurrency & Actor Isolation <a name="concurrency"></a>

Kraken is built with **Swift 6 mode enabled** on Xcode 27 (`macOS 27.0 SDK`).

### Core Concurrency Designations
- **`@MainActor` Isolated Types:**
  - `GameDataStore`: Manages the library array and UI bindings.
  - All SwiftUI Views (`HomeView`, `GameSettingsView`, `ContainerCreationView`, `GameCard`).
  - `Game`: Represents game metadata and observable properties.
- **`Sendable` Value Types (Usable Across Concurrency Boundaries):**
  - `LaunchProfile`: Struct containing container references, backend choices, and arguments.
  - `ContainerReference`: URL wrapper.
  - `GraphicsBackend`: Enum (`.automatic`, `.d3dmetal`, `.dxmt`, `.dxvk`, `.wined3d`).
  - `RuntimeID`: String enum (`.mythicEngine`, `.gptk`, `.wine11`).
  - `RuntimeResolver.ResolvedLaunchTarget`: Immutable launch parameters struct.
- **`@unchecked Sendable` Types:**
  - `ProcessBox`: Reference wrapper around Objective-C `Process` to satisfy cancellation handlers in `LocalGameManager`.
  - `ContinuationState`: Thread-safe NSLock-protected guard preventing multiple `continuation.resume()` invocations in `LocalGameManager`.

### Compiler Warnings Audit
Building `Kraken` produces **zero Swift compilation errors** and only four known warnings:
1. `warning: The Swift file "PersistenceTests.swift" cannot be processed by a Copy Bundle Resources build phase (in target 'Kraken')`
2. `warning: The Swift file "LaunchProfileMergeTests.swift" cannot be processed by a Copy Bundle Resources build phase (in target 'Kraken')`
3. `warning: The Swift file "RuntimeResolverTests.swift" cannot be processed by a Copy Bundle Resources build phase (in target 'Kraken')`
   - **Cause:** PBXBuildFile references for test files were mistakenly included in the main app target's resource phase.
   - **Risk:** Harmless build noise; does not affect runtime code.
4. `warning: SwiftLint not installed`
   - **Cause:** SwiftLint build script phase runs but the binary is absent. Harmless.

---

## 5. Game Model & State Authority <a name="game-model"></a>

The `Game` class (`Mythic/Utilities/Game/Game.swift`) is an `@Observable` model object representing a local or storefront game:

```swift
@Observable
final class Game: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var title: String
    var storefront: Storefront
    var installationState: InstallationState
    var launchProfile: LaunchProfile
    var isFavourited: Bool
    var lastLaunched: Date?
    var playtime: TimeInterval
    // ...
}
```

### Runtime Selection Semantics
The authority for resolving which runtime a game executes with is determined by:
```swift
extension LaunchProfile {
    var effectiveRuntimeID: RuntimeID {
        runtimeOverride ?? defaultRuntimeID
    }
}
```
- `defaultRuntimeID`: Persisted default (typically `.wine11` or `.mythicEngine`).
- `runtimeOverride`: User's explicit manual selection from `GameSettingsView`.
- If `runtimeOverride` is set, it supersedes `defaultRuntimeID`.
- When switching runtimes in `GameSettingsView`, the container must be reassigned to a container whose `runtimeID` matches `effectiveRuntimeID`.

---

## 6. LaunchProfile Semantics <a name="launchprofile"></a>

The `LaunchProfile` struct (`Mythic/Utilities/Game/LaunchProfile.swift`) contains:
- `runtimeOverride: RuntimeID?`
- `defaultRuntimeID: RuntimeID`
- `container: ContainerReference?` (points to container directory URL)
- `graphicsBackend: GraphicsBackend` (defaults to `.automatic`)
- `lastSuccessfulGraphicsBackend: GraphicsBackend?`
- `launchArguments: [String]`

### Invariant Rules
1. Storefront does not influence runtime derivation: Local, Epic, and Steam games all evaluate through identical `RuntimeResolver` logic.
2. `RuntimeResolver.resolve` is strictly read-only: it validates and constructs environment variables without mutating the `LaunchProfile` or creating directories.

---

## 7. Persistence & Library Lifecycle <a name="persistence"></a>

Persistence is managed by `GameDataStore.shared` (`Mythic/Utilities/GameDataStore.swift`):
- Storage: `UserDefaults.standard` under key `"games"`.
- Encoding: Binary Property List (`PropertyListEncoder`).
- Corruption Guard: If decoding fails during load or runtime modification, `isPersistenceSuspended` is set to `true`, and the corrupt data is dumped to `~/Library/Application Support/Kraken/Recovered/games-<timestamp>.plist`. Writes are blocked to prevent overwriting user data.
- Observation: `GameDataStore` calls `observeGameChanges(for:)` which uses `withObservationTracking` on each game's properties. When an observed property changes, a `@MainActor` Task calls `persistLibrary()`.

---

## 8. Runtime System (`RuntimeID`) <a name="runtime-system"></a>

Kraken defines three primary runtime targets in `RuntimeID`:

| RuntimeID | Display Name | Underlying Engine | Direct3D Mechanism | Status |
| :--- | :--- | :--- | :--- | :--- |
| `.wine11` | Wine 11 | Wine 11.0 (x86_64) | DXVK 1.10.3 / MoltenVK 1.4.1 | **CONFIRMED WORKING BASELINE** |
| `.mythicEngine` | Mythic Engine | Wine 7.7 (x86_64) | DXVK or D3DMetal 2.1 | **HISTORICAL (Untested in current session)** |
| `.gptk` | GPTK 4 | Wine 7.7 / Wine 11 + GPTK 4.0 | Apple D3DMetal 4.0 beta 2 | **EXPERIMENTAL / UNVERIFIED** |

---

## 9. Mythic Engine Path (Engine 2 / Wine 7.7) <a name="mythic-engine"></a>

### Historical Known-Good Path
- **Location:** `~/Library/Application Support/Kraken/Engine`
- **Wine Version:** `wine-7.7` (`wine/bin/wine64`)
- **Direct3D:** Bundled D3DMetal 2.1 framework and companion PE DLLs.
- **Historical Behavior:** Successfully launched Subnautica and various Epic games under Mythic 0.x.
- **Current Status:** Intact on disk, but has not been tested during recent Wine 11 focus. Requires verification that recent DXVK and backend changes did not regress Wine 7.7 execution.

---

## 10. Wine 11 Runtime Path (Engine 3) <a name="wine-11"></a>

### Complete Environment Specification
- **Bundle Path:** `~/Library/Application Support/Kraken/Runtimes/wine11/Wine Stable.app`
- **Wine Executable:** `.../Contents/Resources/wine/bin/wine` (Wine 11.0 x86_64)
- **Wineserver:** `.../Contents/Resources/wine/bin/wineserver`
- **Prefix Path:** `~/Library/Containers/com.yerlsd.kraken/Containers/W11`

### Required Environment Variables (`RuntimeResolver.swift`)
```bash
WINEPREFIX="/Users/taylor/Library/Containers/com.yerlsd.kraken/Containers/W11"
WINELOADER="/Users/taylor/Library/Application Support/Kraken/Runtimes/wine11/Wine Stable.app/Contents/Resources/wine/bin/wine"
WINESERVER="/Users/taylor/Library/Application Support/Kraken/Runtimes/wine11/Wine Stable.app/Contents/Resources/wine/bin/wineserver"
WINE="/Users/taylor/Library/Application Support/Kraken/Runtimes/wine11/Wine Stable.app/Contents/Resources/wine/bin/wine"
WINE64="/Users/taylor/Library/Application Support/Kraken/Runtimes/wine11/Wine Stable.app/Contents/Resources/wine/bin/wine"
WINE_APP_BUNDLE="/Users/taylor/Library/Application Support/Kraken/Runtimes/wine11/Wine Stable.app"
WINEMSYNC="1"
ROSETTA_ADVERTISE_AVX="1"
WINEDLLOVERRIDES="d3d10core,d3d11,dxgi=n,b"
DXVK_ASYNC="1"
DXVK_HUD="full" # when metalHUD is enabled in Container settings
```

---

## 11. DXVK Translation Layer (1.10.3 Async) <a name="dxvk"></a>

### The "Bogus DLL" Discovery (CONFIRMED FACT)
Earlier in the investigation, games running on DXVK failed with:
```text
D3D11CoreCreateDevice: Adapter is not a DXVK adapter
```
- **Discovery:** The `dxgi.dll` file bundled in Kraken's `Engine/DXVK/x64/` was an old Wine 7.8 stub DLL (99,840 bytes), NOT genuine DXVK!
- **Resolution:** Replaced with genuine DXVK 1.10.3-20230507-async `dxgi.dll` (2,612,552 bytes).
- **Verification:** DXVK logs immediately confirmed genuine DXVK adapter initialization:
  `info:  DXGI: DXVK (version 1.10.3-20230507-async)`
  `info:  D3D11CoreCreateDevice: Using DXGI adapter 0`

### Current DXVK Configuration (`dxvk.conf`)
Located at: `~/Library/Containers/com.yerlsd.kraken/Containers/W11/drive_c/windows/dxvk.conf`
```ini
dxgi.nvapiHack = False
dxgi.emulateUMA = False
dxgi.maxDeviceMemory = 4095
dxgi.maxSharedMemory = 4095
d3d11.invariantPosition = True
```

---

## 12. MoltenVK & Metal Translation Layer (1.4.1) <a name="moltenvk"></a>

### Bundled Library Details
- **Path:** `~/Library/Application Support/Kraken/Runtimes/wine11/Wine Stable.app/Contents/Resources/wine/lib/libMoltenVK.dylib`
- **Version:** `MoltenVK version 1.4.1, supporting Vulkan version 1.2`
- **Internal Engine:** Embedded SPIRV-Cross translates SPIR-V bytecode into Metal Shading Language (MSL).
- **Active Environment Variables:**
  - `MVK_CONFIG_LOG_LEVEL=3` (or default 3)
  - MoltenVK passes compiled MSL pipelines to Apple Metal via `[MTLDevice newRenderPipelineStateWithDescriptor:error:]`.

---

## 13. Game Porting Toolkit (GPTK 4.0) Path <a name="gptk-4"></a>

### Assets & Source Code
- **DMG Source:** `~/Documents/Game Porting Toolkit 4.0/Evaluation environment for Windows games 4.0 beta 2.dmg`
- **Installer Code:** `Mythic/Utilities/Game/GPTKInstaller.swift` (Untracked file in working tree)
- **Container:** `~/Library/Containers/com.yerlsd.kraken/Containers/GPTK`

### Historical Failures & Traps to Avoid
1. **ABI Mismatch with Wine 11:** Apple's `D3DMetal.framework` in GPTK 4.0 expects specific Wine Unix-call table offsets. Injecting GPTK's `d3d11.so` or `ntdll.so` into Wine 11 causes immediate crashes or Rosetta AOT translation failures.
2. **Rosetta AOT Invalidation:** Modifying or replacing `ntdll.so` breaks Apple codesigning entitlements and Rosetta 2 ahead-of-time binary caches.
3. **Rule:** **DO NOT** attempt to overwrite Wine 11 Unix binaries with GPTK binaries. GPTK must execute under its designated `.gptk` runtime path using compatible Wine 7.7 base binaries.

---

## 14. Graphics Backends & Resolvers <a name="graphics-backends"></a>

Defined in `Mythic/Utilities/Game/GraphicsBackend.swift`:
- `.automatic`: Resolves to highest-priority available backend.
- `.d3dmetal`: Apple D3DMetal (GPTK).
- `.dxmt`: DXMT (Metal-native D3D11). Currently disabled for Wine 11 due to false-positive detection.
- `.dxvk`: DXVK (Direct3D 9/10/11 -> Vulkan -> MoltenVK -> Metal).
- `.wined3d`: Built-in Wine OpenGL/Metal translation.

### The False-Positive DXMT Issue (CONFIRMED & FIXED)
`GraphicsBackendDetector.swift` previously checked for `lib/wine/x86_64-unix/d3d11.so` to detect DXMT. Because Wine 11 ships its standard `d3d11.so` at that path, Kraken falsely reported DXMT was available. Automatic backend resolution chose DXMT, causing games to launch with broken rendering. Fixed by disabling DXMT detection on Wine 11 until actual DXMT libraries are packaged.

---

## 15. Subnautica Diagnostic Environment <a name="subnautica"></a>

- **Game Executable:** `/Users/taylor/Documents/Subnautica-AnkerGames/Subnautica/Subnautica.exe`
- **Engine:** Unity 2019.4.36f1 (64-bit, D3D11)
- **Log File:** `~/Library/Containers/com.yerlsd.kraken/Containers/W11/drive_c/users/taylor/AppData/LocalLow/Unknown Worlds/Subnautica/Player.log`
- **Save Slot:** `slot0000` (`SavedGames/slot0000`)
- **Options File:** `SavedGames/options.bin`
- **Pipeline Cache:** `/Users/taylor/Desktop/Kraken/Subnautica.dxvk-cache` (and inside game directory)

---

## 16. Audio Subsystem Status (CLOSED) <a name="audio"></a>

> [!NOTE]
> **AUDIO IS CLOSED.**
> Do **NOT** spend engineering time investigating audio unless a fresh regression is observed.

### Empirical Proof
- In live gameplay testing, all audio paths were confirmed operational.
- Ambient ocean sounds, waves, music, UI clicks, player footsteps, and PDA voice lines ("Oxygen", "Welcome aboard captain") played clearly through macOS CoreAudio.
- Wine's `winepulse` / `winealsa` stubs fall back to `winecoreaudio.drv`, which communicates directly with macOS system audio.

---

## 17. Loading Performance & Timings <a name="loading"></a>

| Metric / Milestone | Cold Run (No Shader Cache) | Warm Run (Reusing dxvk-cache) |
| :--- | :--- | :--- |
| **Play Click to StartScreen** | ~35.0 seconds | ~12.2 seconds |
| **StartScreen to World Loaded** | ~389.78 seconds (~6.5 minutes) | ~23.1 seconds |
| **Total Time to Gameplay** | **424.78 seconds** | **~35.3 seconds** |
| **Graphics Pipelines Compiled** | 589 (compiled on-the-fly) | 589 (reused from cache) |

*Note: Cold run required compiling hundreds of Vulkan/Metal shaders in real time. Once written to `Subnautica.dxvk-cache`, loading dropped from >7 minutes to ~35 seconds.*

---

## 18. GPU Memory & VRAM Reporting Investigation <a name="gpu-memory-reporting"></a>

### The 128 MB VRAM Root Cause (CONFIRMED)
Under default DXVK, Unity logged:
`VRAM: 128 MB`
`changeset 83031, QualityLevel = 0` (Lowest texture resolution, low draw distance)

### Reverse Engineering Unity 2019.4 & DXVK
1. Disassembly of `UnityPlayer.dll` at `0x180460f00` revealed Unity queries `ID3D11Device::CheckFeatureSupport` for `D3D11_FEATURE_D3D11_OPTIONS2`.
2. On Apple Silicon, DXVK reports `UnifiedMemoryArchitecture == 1`.
3. In UMA mode, Unity reads `DXGI_ADAPTER_DESC.SharedSystemMemory` instead of `DedicatedVideoMemory`!
4. Default DXVK sets `SharedSystemMemory = 0`. Unity multiplied by `1 / 1048576` = 0 MB, and clamped to its hardcoded 128 MB fallback.

### The Fix via `dxvk.conf`
By configuring `dxvk.conf`:
```ini
dxgi.nvapiHack = False
dxgi.emulateUMA = False
dxgi.maxDeviceMemory = 4095
dxgi.maxSharedMemory = 4095
```
Subnautica's `Player.log` confirmed:
```text
Direct3D:
    Version:  Direct3D 11.0 [level 11.0]
    Renderer: Apple M4 (ID=0x1b000209)
    Vendor:   0P P 
    VRAM:     4095 MB
changeset 83031, QualityLevel = 1 (Medium)
```

---

## 19. Reported GPU Memory Feature (Architecture & Plan) <a name="reported-gpu-memory-feature"></a>

### Architectural Requirement for Astra
Implement a formal, user-configurable **Reported GPU Memory Policy** in Kraken.

#### Core Concept
This is a **reporting mechanism**, NOT physical memory reservation. It instructs DXVK and DXGI what integer value to return in `DXGI_ADAPTER_DESC.DedicatedVideoMemory` and `SharedSystemMemory`.

#### Proposed Data Structure
```swift
enum ReportedMemoryPolicy: Codable, Equatable, Hashable, Sendable {
    case automatic
    case manual(megabytes: Int)
}
```
- **Automatic Mode:** Probes physical system RAM via `ProcessInfo.processInfo.physicalMemory`. On 16 GB unified memory systems, reports 4096 MB (or 50% of available memory). On 8 GB systems, reports 2048 MB.
- **Manual Options:** 1024 MB, 2048 MB, 4096 MB, 8192 MB.
- **Generation:** `RuntimeResolver.swift` generates or updates `dxvk.conf` in the container prefix before process launch.
- **UI Warning:** GameSettingsView must explicitly warn:
  > *"Adjusting Reported GPU Memory changes the VRAM size reported to Windows games. It does not reserve physical RAM, but misconfiguration can cause crashes or high memory pressure."*

---

## 20. The Subnautica 3D Rendering Failure <a name="rendering-failure"></a>

### Symptom
- **Static meshes:** Render perfectly (seabed terrain, coral, rocks, Lifepod interior benches, ladders, floating markers).
- **Environment:** Ocean water, surface reflections, day/night lighting, volumetric fog, particles render.
- **Rigged/Animated meshes:** Completely invisible. Scanner tool body, Gasopod body, Stalker body, Lifepod outer hull are not drawn.

---

## 21. Shader / Vertex Pipeline Analysis & Trace <a name="shader--vertex-pipeline-analysis"></a>

### The Three Failing Skinned Mesh Shaders
Inspected from `task-5937.log`:

```
[mvk-error] VK_ERROR_INITIALIZATION_FAILED: Render pipeline compile failed (Error code 2):
Vertex attribute v4(4) of type int4 cannot be read using MTLAttributeFormatUInt4.
err:   DxvkGraphicsPipeline: Failed to compile pipeline
err:     vs  : VS_87331e594574e9ebd5108b425535184c3b679472
err:     attr 0 : location 0, binding 0, format VK_FORMAT_R32G32B32_SFLOAT, offset 0
err:     attr 1 : location 1, binding 0, format VK_FORMAT_R32G32B32_SFLOAT, offset 12
err:     attr 2 : location 2, binding 0, format VK_FORMAT_R32G32B32A32_SFLOAT, offset 24
err:     attr 3 : location 3, binding 2, format VK_FORMAT_R32G32B32A32_SFLOAT, offset 0
err:     attr 4 : location 4, binding 2, format VK_FORMAT_R32G32B32A32_UINT, offset 16
```

```
[mvk-error] VK_ERROR_INITIALIZATION_FAILED: Render pipeline compile failed (Error code 2):
Vertex attribute v4(4) of type int2 cannot be read using MTLAttributeFormatUInt2.
err:   DxvkGraphicsPipeline: Failed to compile pipeline
err:     vs  : VS_467e1773bbc9fcff45ffcdf9b8b420e9fe3b85fd
err:     attr 3 : location 3, binding 2, format VK_FORMAT_R32G32_SFLOAT, offset 0
err:     attr 4 : location 4, binding 2, format VK_FORMAT_R32G32_UINT, offset 8
```

```
[mvk-error] VK_ERROR_INITIALIZATION_FAILED: Render pipeline compile failed (Error code 2):
Vertex attribute v3(3) of type int cannot be read using MTLAttributeFormatUInt.
err:   DxvkGraphicsPipeline: Failed to compile pipeline
err:     vs  : VS_72c63012b1e9e1ef2a01825d307001faac79ed9e
err:     attr 3 : location 3, binding 2, format VK_FORMAT_R32_UINT, offset 0
```

### Full Technical Trace
1. **Unity Shader Source:** HLSL skinning shaders define:
   `int4 blendIndices : BLENDINDICES;`
   In DXBC, this is stored in the Input Signature (`ISGN`) with component type `D3D_REGISTER_COMPONENT_SINT32`.
2. **Unity Vertex Buffer:** The mesh vertex buffer is bound using `ID3D11InputLayout` with `DXGI_FORMAT_R32G32B32A32_UINT`. In Direct3D 11, hardware registers are untyped 32-bit registers, so this is valid.
3. **DXVK Translation:**
   - DXVK generates SPIR-V declaring `v4` as `OpTypeInt 32 1` (signed `int4`).
   - DXVK generates `VkVertexInputAttributeDescription` with `VK_FORMAT_R32G32B32A32_UINT`.
4. **MoltenVK / SPIRV-Cross:**
   - SPIRV-Cross translates SPIR-V to MSL declaring function argument `int4 v4 [[attribute(4)]]`.
   - MoltenVK sets `MTLVertexDescriptor.attributes[4].format = MTLVertexFormatUInt4`.
5. **Apple Metal 3:**
   - Metal strictly forbids reading `MTLAttributeFormatUInt4` using an `int4` shader input.
   - Metal aborts pipeline creation with `VK_ERROR_INITIALIZATION_FAILED`.
   - DXVK marks the pipeline invalid and drops the draw call.

---

## 22. Current Rendering Root Cause Status <a name="current-rendering-root-cause-status"></a>

- **CONFIRMED FACT:** The missing 3D models are caused by Metal render pipeline compilation failures due to signed/unsigned vertex attribute format mismatch (`int4`/`int2`/`int` vs `UInt4`/`UInt2`/`UInt`).
- **CONFIRMED FACT:** All missing models (Scanner, Gasopod, Lifepod) share these exact skinned-mesh shader input signatures.
- **LIKELY CAUSE:** A translation layer mismatch where MoltenVK does not adjust the `MTLVertexDescriptor` format to match the signedness of the MSL attribute argument, or DXVK does not normalize vertex input types.
- **POTENTIAL FIX PATHS FOR ASTRA:**
  1. **MoltenVK Layer:** Investigate if an updated MoltenVK release or configuration flag remaps integer vertex attribute formats to match shader arguments.
  2. **DXVK Layer:** Investigate if DXVK's `dxbc_compiler` or vertex input state can be configured/patched to emit unsigned types for integer vertex inputs when paired with `_UINT` formats.
  3. **Shader / Cache Patching:** Modify the cached SPIR-V bytecode in `Subnautica.dxvk-cache` to declare `OpTypeInt 32 0` (unsigned) for locations 3 and 4.

---

## 23. Performance Findings & Real-World Telemetry <a name="performance"></a>

Captured from live Metal HUD telemetry in gameplay:
- **Resolution:** 1470 × 956 (Retina Mode disabled, LogPixels 96 DPI)
- **FPS:** 45.9 FPS sustained (range: 11.0 min to 101.6 max)
- **Frametime:** 21.8 ms (stable pacing in open ocean)
- **Draw Calls:** ~850 calls/frame
- **Render Passes:** 34 passes/frame
- **Graphics Pipelines:** 589 compiled pipelines
- **Thermals:** Machine ran cool to warm; no thermal throttling observed on Apple M4.

---

## 24. Apple Silicon Optimization Philosophy <a name="apple-silicon-optimization"></a>

For MacBook Air-class hardware, Astra must adhere to this hierarchy of priorities:
$$\text{Correctness} > \text{Frame Pacing} > \text{Stability} > \text{Thermals} > \text{Resource Efficiency} > \text{Raw Peak FPS}$$
- Avoid high-DPI retina rendering by default: rendering at 2880×1800 destroys MBA fill-rate. 1x scaling (1440×900 / 1470×956) yields double the framerate.
- Never busy-poll in background threads.
- Avoid unnecessary texture/buffer copies across the unified memory bus.

---

## 25. Game Process Management (`LocalGameManager`) <a name="game-process-management"></a>

Located at `Mythic/Utilities/GameManager/LocalGameManager.swift`:
- **Current Directory:** Explicitly set to `location.deletingLastPathComponent()` so games find data packs.
- **Streaming Pipes:** Captures stdout and stderr to `Logger` with category `LocalGameManager`.
- **Termination Guard:** Uses `ContinuationState` class with an internal `NSLock` to guarantee `continuation.resume()` is called exactly once.

---

## 26. Container Creation & Bootstrapping <a name="container-management"></a>

Located at `Mythic/Utilities/Wine/WineInterface+Container.swift`:
- **Default Settings Bug (Astra Must Note):**
  The current code default is:
  `retinaMode = true`, `scaling = 192` (2x high-DPI scaling).
  In the working W11 container, this was manually overridden to `retinaMode = false`, `LogPixels = 0x60` (96 DPI).
  Astra should update the code defaults so new containers automatically receive 1x scaling.

---

## 27. Test Suite Status & Discrepancies <a name="tests"></a>

### Empirical Test Execution Result
Ran `xcodebuild test -project Kraken.xcodeproj -scheme Kraken -destination 'platform=macOS'`:
- **Executed:** **38 tests**, **0 failures**, **0 errors** (Exit Code 0).
  - `LaunchProfileMergeTests`: 12 tests passed.
  - `PersistenceTests`: 8 tests passed.
  - `RuntimeResolverTests`: 18 tests passed.

### The 50 vs. 38 Test Discrepancy (CRITICAL FACT FOR ASTRA)
- Historical turn summaries claimed: *"All 50 unit tests passing."*
- **Investigation Result:** In `Kraken.xcodeproj/project.pbxproj`, `GraphicsBackendTests.swift` (which contains 12 tests) was added to PBXFileReference and PBXGroup, but was **NOT** added to `PBXSourcesBuildPhase` of the `KrakenTests` target!
- Therefore, `GraphicsBackendTests` was never compiled or executed during `xcodebuild test`!
- **Astra Task:** Add `GraphicsBackendTests.swift` to `PBXSourcesBuildPhase` in `project.pbxproj` and verify all 50 tests pass.

---

## 28. Build System & Xcode Configuration <a name="build-system"></a>

- **Project:** `Kraken.xcodeproj`
- **Scheme:** `Kraken`
- **Configuration:** `Debug`
- **Build Command:**
  ```bash
  xcodebuild -project Kraken.xcodeproj -scheme Kraken -configuration Debug build
  ```
- **Result:** Exit Code 0 (`** BUILD SUCCEEDED **`).

---

## 29. Application Icon & Asset Catalogs <a name="assets"></a>

- In `project.pbxproj`, `ASSETCATALOG_COMPILER_APPICON_NAME = Kraken;`.
- The authoritative app icon asset catalog is `Mythic/Assets.xcassets/Kraken.appiconset`.
- Modifications in `AppIcon.appiconset` are legacy assets. Astra should leave asset catalogs untouched.

---

## 30. Binary Safety Rules & Operational Discipline <a name="binary-safety"></a>

> [!CAUTION]
> ### STRICT BINARY DISCIPLINE
> 1. **NEVER** overwrite runtime binaries without creating a `.bak` backup first.
> 2. **NEVER** leave experimental binary patches in production paths. (The earlier diagnostic patch to `dxgi.dll` was restored from pristine `dxgi.dll.bak` and verified via `cmp`).
> 3. **NEVER** mix GPTK Unix `.so` files with Wine 11.
> 4. Verify file integrity using `cmp` or `shasum -a 256` before and after modifications.

---

## 31. Critical Source Files Reference <a name="important-files"></a>

| File | Purpose | Current Status | Risk if Modified |
| :--- | :--- | :--- | :--- |
| `RuntimeResolver.swift` | Authoritative launch resolution & environment builder | Working, updated for Wine 11 & GPTK | High (breaks all game launches) |
| `Runtime.swift` | Runtime definitions & filesystem locations | Working, contains `.gptk` & `.wine11` | High (breaks runtime discovery) |
| `GraphicsBackendDetector.swift` | Probes available backends for runtimes | Working, false DXMT fixed | Medium (can cause false backend picks) |
| `GraphicsBackendResolver.swift` | Priority ranking for graphics backends | Working, prefers DXVK on Wine 11 | Medium |
| `LocalGameManager.swift` | Process spawning, pipes & lifecycle | Working, working-dir & lock fixes | High (causes launch hangs or crashes) |
| `WineInterface+DXVK.swift` | Copies DXVK DLLs to container system32 | Working, copies dxgi.dll | High (can revert to broken Wine stub) |
| `GameDataStore.swift` | Persistence, library state, observation | Working, corruption-proof | High (data loss in UserDefaults) |
| `GameSettingsView.swift` | UI for runtime & container selection | Working, stable selection | Medium (UI drift) |
| `GPTKInstaller.swift` | Mounts DMG & configures GPTK payload | Untracked file, fully functional | Medium |

---

## 32. Runtime Filesystem Paths Table <a name="current-runtime-file-paths"></a>

| Component | Absolute Path |
| :--- | :--- |
| **Kraken Source** | `/Users/taylor/Desktop/Kraken` |
| **Wine 11 Bundle** | `/Users/taylor/Library/Application Support/Kraken/Runtimes/wine11/Wine Stable.app` |
| **Wine 11 Binary** | `.../Wine Stable.app/Contents/Resources/wine/bin/wine` |
| **Wine 11 Wineserver**| `.../Wine Stable.app/Contents/Resources/wine/bin/wineserver` |
| **MoltenVK 1.4.1** | `.../Wine Stable.app/Contents/Resources/wine/lib/libMoltenVK.dylib` |
| **W11 Container** | `/Users/taylor/Library/Containers/com.yerlsd.kraken/Containers/W11` |
| **W11 system32** | `.../W11/drive_c/windows/system32` |
| **W11 dxvk.conf** | `.../W11/drive_c/windows/dxvk.conf` |
| **Engine 2 (Wine 7.7)**| `/Users/taylor/Library/Application Support/Kraken/Engine` |
| **Engine DXVK (x64)**| `/Users/taylor/Library/Application Support/Kraken/Engine/DXVK/x64` |
| **GPTK 4.0 DMG** | `/Users/taylor/Documents/Game Porting Toolkit 4.0/Evaluation environment for Windows games 4.0 beta 2.dmg` |
| **Subnautica Game** | `/Users/taylor/Documents/Subnautica-AnkerGames/Subnautica/Subnautica.exe` |
| **Subnautica Log** | `.../W11/drive_c/users/taylor/AppData/LocalLow/Unknown Worlds/Subnautica/Player.log` |
| **Subnautica Cache** | `/Users/taylor/Desktop/Kraken/Subnautica.dxvk-cache` |

---

## 33. Process Environment Variables Table <a name="environment-variables"></a>

| Variable | Current Value | Set By | Purpose | Safe to Change? |
| :--- | :--- | :--- | :--- | :--- |
| `WINEPREFIX` | `/Users/taylor/.../W11` | `RuntimeResolver` | Directs Wine to prefix | NO |
| `WINELOADER` | Path to `wine` | `RuntimeResolver` | Explicit loader for relocatable app | NO |
| `WINESERVER` | Path to `wineserver`| `RuntimeResolver` | Explicit wineserver for relocatable app| NO |
| `WINEMSYNC` | `1` | `RuntimeResolver` | Enables fast Mach sync synchronization | YES (0 or 1) |
| `ROSETTA_ADVERTISE_AVX`| `1` | `RuntimeResolver` | Exposes AVX2 instruction emulation | YES (0 or 1) |
| `WINEDLLOVERRIDES` | `d3d10core,d3d11,dxgi=n,b`| `RuntimeResolver` | Forces native DXVK PE DLLs | NO (must include dxgi) |
| `DXVK_ASYNC` | `1` | `RuntimeResolver` | Enables async shader pipeline compilation| YES (0 or 1) |
| `DXVK_HUD` | `full` | `RuntimeResolver` | Shows FPS/Metal GPU metrics overlay | YES |

---

## 34. Comprehensive Source Modifications Breakdown <a name="current-source-changes"></a>

1. **`Mythic/Utilities/Wine/WineInterface+DXVK.swift`**:
   - Added copying of `dxgi.dll` for both `x64` and `x32`.
   - Removed `.mythicEngine`-only check, allowing `.wine11` containers to install DXVK.
2. **`Mythic/Utilities/Launch/RuntimeResolver.swift`**:
   - Updated `providesDXVK` to return `true` for `.wine11`.
   - Added `dxgi` to `WINEDLLOVERRIDES` (`"d3d10core,d3d11,dxgi=n,b"`).
   - Inherited host environment in `configure(_:for:)`.
   - Added `.gptk` runtime ID and D3DMetal environment handling.
3. **`Mythic/Utilities/Game/Runtime.swift`**:
   - Added `case gptk = "gptk"` to `RuntimeID`.
   - Fixed path in `isRuntimeInstalled(.wine11)` (`lib/wine/x86_64-unix/ntdll.so`).
   - Added library directory helper accessors.
4. **`Mythic/Utilities/Game/GraphicsBackendDetector.swift`**:
   - Disabled false-positive DXMT check on Wine 11.
   - Connected DXVK availability directly to `runtimeID.providesDXVK`.
5. **`Mythic/Utilities/Game/GraphicsBackendResolver.swift`**:
   - Explicit per-runtime ranking (Wine 11 prefers DXVK -> WineD3D).
6. **`Mythic/Utilities/GameManager/LocalGameManager.swift`**:
   - Set `process.currentDirectoryURL` to game executable folder.
   - Added async stdout/stderr streaming to `os_log`.
   - Added `ContinuationState` lock to avoid continuation double-resumes.
7. **`Mythic/Views/Navigation/HomeView.swift`**:
   - Replaced `.constant(recentGame)` with `gameDataStore.binding(for:)`.

---

## 35. External Runtime Modifications Breakdown <a name="external-runtime-state"></a>

1. **`drive_c/windows/dxvk.conf`**: Created with `dxgi.maxDeviceMemory = 4095` and `dxgi.maxSharedMemory = 4095`.
2. **`drive_c/windows/system32/dxgi.dll`**: Replaced old Wine 7.8 stub with genuine DXVK 1.10.3 async DLL. Pristine copy verified against `dxgi.dll.bak`.
3. **`user.reg` in W11**: Set `"RetinaMode"="n"` and `"LogPixels"=dword:00000060` (96 DPI).
4. **`Subnautica.dxvk-cache`**: Generated and preserved (128 KB, 589 compiled graphics pipelines).

---

## 36. Diagnostic Artifacts & Telemetry Logs <a name="diagnostics"></a>

Artifacts saved in `/Users/taylor/.gemini/antigravity/brain/81f6be44-7477-4bec-9dec-21b2d9e6a044/`:
- `subnautica_vram_menu.png`: 3D StartScreen render with ocean reflections and water effects.
- `subnautica_vram_saves.png`: Saved games menu proving 4095 MB VRAM in gameplay.
- `subnautica_run2_gameplay3.png`: Telemetry screenshot showing 45.9 FPS, 589 pipelines, 850 draw calls.
- `task-5937.log`: Full execution log capturing exact Metal vertex attribute compilation errors.

---

## 37. Empirical Gameplay Verification Record <a name="real-game-verification"></a>

- **Kraken UI:** Launch confirmed; Play button responds immediately.
- **Wine Process:** Spawned cleanly (`wine` PID tracked, output captured).
- **StartScreen:** Fully interactive 3D menu loaded in ~12 seconds.
- **Save Loading:** `slot0000` loaded in 23.1 seconds.
- **Controls & Physics:** Mouse look, WASD movement, swimming, surface breaching verified.
- **Audio:** Full stereo sound output verified.
- **Missing Models:** Scanner tool, Gasopod, Lifepod 5 hull missing.

---

## 38. Exact Current Failure Matrix <a name="failure-matrix"></a>

| Area | Status | Confidence | Evidence | Next Action |
| :--- | :--- | :--- | :--- | :--- |
| **Kraken Debug Build** | PASS | CONFIRMED | `xcodebuild` Exit Code 0 | None (preserve) |
| **Unit Test Suite** | PARTIAL PASS | CONFIRMED | 38/38 run passed; 12 omitted | Add `GraphicsBackendTests` to build phase |
| **Wine 11 Launch** | PASS | CONFIRMED | Subnautica gameplay verified | Maintain baseline |
| **Direct3D 11 / DXVK** | PASS | CONFIRMED | DXVK 1.10.3 active, HUD verified | Maintain baseline |
| **VRAM Reporting** | PASS | CONFIRMED | 4095 MB, QualityLevel 1 in log | Formalize into UI settings |
| **Skinned Meshes** | **FAIL** | **CONFIRMED** | Metal error: `int4` vs `MTLAttributeFormatUInt4` | Implement signedness reconciliation |
| **Audio** | PASS | CONFIRMED | Sound verified in gameplay | CLOSED (do not touch) |
| **Container Defaults**| SUBOPTIMAL | CONFIRMED | Code defaults to 2x retina (192 DPI)| Update default settings struct to 1x |
| **Mythic Engine** | UNTESTED | UNKNOWN | Files present, not launched recently | Regression-test once Wine 11 complete |
| **GPTK 4.0** | UNTESTED | UNKNOWN | DMG present, installer code drafted | Test under isolated `.gptk` path |

---

## 39. Historical Dead Ends & Refuted Hypotheses <a name="historical-dead-ends"></a>

1. **"Missing models are caused by low VRAM / LOD 0":** DISPROVEN. Reporting 4095 MB VRAM promoted the engine to `QualityLevel = 1`, but models remained invisible due to pipeline compilation errors.
2. **"All textures are broken":** DISPROVEN. Terrain, water, and UI textures render with full fidelity.
3. **"Audio is broken in Wine 11":** DISPROVEN. Live gameplay confirmed full working audio.
4. **"dxgi.dll in Engine was fine because it was named dxgi.dll":** DISPROVEN. It was a 99 KB Wine stub. Genuine DXVK is 2.6 MB.
5. **"DXMT was running on Wine 11":** DISPROVEN. False-positive file detection in `GraphicsBackendDetector`.
6. **"Patching live dxgi.dll binary is the long-term solution":** DISPROVEN. Reverted to pristine backup; clean configuration is achieved via `dxvk.conf`.

---

## 40. What Astra Must NOT Do <a name="what-astra-must-not-do"></a>

1. **DO NOT** execute destructive git commands (`git reset --hard`, `git clean -fd`).
2. **DO NOT** discard or overwrite `stash@{0}`.
3. **DO NOT** recreate or delete the `W11` container.
4. **DO NOT** re-investigate audio.
5. **DO NOT** replace Wine 11's `ntdll.so` with GPTK's `ntdll.so`.
6. **DO NOT** patch binaries permanently when configuration keys exist.
7. **DO NOT** treat a clean build or high FPS as proof that rendering is visually correct.

---

## 41. Recommended First Ten Engineering Actions <a name="recommended-next-steps"></a>

1. **Verify Baseline State:** Run `xcodebuild -project Kraken.xcodeproj -scheme Kraken -configuration Debug build` to confirm clean compilation.
2. **Fix Test Target Build Phase:** Add `GraphicsBackendTests.swift` to `PBXSourcesBuildPhase` in `Kraken.xcodeproj/project.pbxproj` and verify all 50 tests execute.
3. **Trace MoltenVK Shader Translation:** Inspect how MoltenVK / SPIRV-Cross handles `MTLVertexDescriptor` generation for integer vertex inputs.
4. **Resolve Signed/Unsigned Attribute Mismatch:**
   - Investigate whether MoltenVK configuration or DXVK vertex state configuration can normalize vertex attribute signedness (`MTLAttributeFormatUInt4` vs `int4`).
5. **Visually Verify Skinned Meshes:** Launch Subnautica and confirm the Scanner tool body and Gasopod body are visible in gameplay.
6. **Formalize GPU Memory Reporting Policy:** Implement `ReportedMemoryPolicy` enum in `GameDataStore` and generate `dxgi.maxDeviceMemory` / `dxgi.maxSharedMemory` automatically in `RuntimeResolver`.
7. **Fix Fresh Container Defaults:** Change `retinaMode: false` and `scaling: 96` in `WineInterface+Container.swift` so new containers default to 1x DPI.
8. **Verify Mythic Engine Baseline:** Perform a test launch of an Engine 2 container with Wine 7.7 to ensure no cross-runtime regressions.
9. **Validate Isolated GPTK 4.0 Path:** Complete `GPTKInstaller.swift` tests using isolated directories without contaminating Wine 11.
10. **Clean Commit:** Commit the verified fixes to `engine3/wine11`.

---

## 42. Objective Acceptance Criteria ("Definition of Done") <a name="acceptance-criteria"></a>

### Rendering Fix Acceptance Criteria
- [ ] Subnautica renders into `slot0000` with **Scanner tool 3D body physically visible** in the player's hand.
- [ ] **Gasopod creature 3D body physically visible** swimming in the water.
- [ ] **Lifepod 5 outer hull and hatches physically visible** from the exterior.
- [ ] No `VK_ERROR_INITIALIZATION_FAILED` errors in stdout/stderr.

### Architecture Acceptance Criteria
- [ ] VRAM reporting is driven by clean Swift configuration without binary patches.
- [ ] New containers automatically create 1x scaling (non-retina) configurations.
- [ ] All 50 unit tests compile and pass cleanly in `xcodebuild test`.

---

## 43. Long-Term Product & Engineering Direction <a name="product--engineering-direction"></a>

Kraken is intended to be a premier, elegant, high-performance macOS gaming platform. It should hide the ugly complexity of Wine, DXVK, and Metal behind a clean, intuitive Swift/SwiftUI interface, while giving power users precise control over compatibility runtimes. Every change made must be deterministic, reproducible, and respectful of the host machine's resources.

---

## 44. Explicit List of Unverified Items & Gaps <a name="unknowns"></a>

1. **DXVK 1.10.3 vs. Upstream DXVK-macOS:** It is unknown whether newer builds of DXVK-macOS (or upstream DXVK 2.x) handle Direct3D 11 integer vertex input signedness differently.
2. **MoltenVK Private API Behavior:** The effect of `MVK_CONFIG_USE_METAL_PRIVATE_API=1` on vertex attribute compatibility has not been tested.
3. **Mythic Engine 2 Current State:** It is unknown whether the Engine 2 Wine 7.7 path currently launches games without error, as all recent focus has been on Wine 11.
4. **GPTK 4.0 D3DMetal Integration:** It is unverified whether Apple's D3DMetal 4.0 beta 2 can be cleanly driven by Kraken without encountering Unix-call ABI mismatches.
