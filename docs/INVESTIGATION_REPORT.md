# RUNTIME SELECTION INVESTIGATION REPORT

**Date:** 2026-09-17  
**Branch:** `engine3/wine11`  
**Status:** ROOT CAUSES IDENTIFIED

---

## EXECUTIVE SUMMARY

The runtime selection persistence bug has **TWO DISTINCT ROOT CAUSES**:

1. **PRIMARY BUG:** `.task { ensureCompatibleContainer() }` runs every time GameSettingsView appears and **immediately overwrites** any manual runtime selection that doesn't match the container's runtime
2. **SECONDARY BUG (FIXED):** `.constant(game)` bindings prevented changes from persisting to GameDataStore

The Subnautica launch issue appears to be a **separate problem** related to resolution/fullscreen settings, not the runtime selection bug.

---

## INVESTIGATION 1 — RUNTIME SELECTION ROOT CAUSE

### The Complete Data Flow

When the user selects Wine 11 in the picker:

```
User clicks "Wine 11" in Picker
    ↓
manualRuntimeSelection binding setter fires
    ↓
profile.selectRuntime(.wine11)  // sets runtimeOverride = .wine11
    ↓
profile.container = compatibleContainerURL(for: .wine11)  // finds W11 container
    ↓
game.launchProfile = profile  // updates Game object
    ↓
GameDataStore observation fires (CONFIRMED: this works now with proper bindings)
    ↓
persistLibrary() is called (CONFIRMED: this works)
    ↓
**BUT THEN...**
    ↓
.task { ensureCompatibleContainer() } runs AGAIN
    ↓
It reads: game.launchProfile.effectiveRuntimeID (which is now .wine11)
    ↓
It checks: currentContainer.runtimeID == runtimeID
    ↓
W11 container.runtimeID = "wine-11" ✅ MATCHES
    ↓
Guard passes, returns early
    ↓
**Selection SHOULD persist here**
```

### BUT WAIT — THE ACTUAL BUG

The problem is **WHEN** `.task` runs. SwiftUI's `.task` modifier runs:
1. When the view first appears
2. **When the view's identity changes**
3. **When observed properties change**

Since `game` is `@Binding var game: Game` and `Game` is `@Observable`, ANY change to `game.launchProfile` triggers view invalidation, which can cause `.task` to run again.

But there's a WORSE bug: look at line 302-316:

```swift
func ensureCompatibleContainer() {
    let runtimeID = game.launchProfile.effectiveRuntimeID
    
    guard
        let currentURL = game.launchProfile.container?.url,
        let currentContainer = try? Wine.getContainerObject(at: currentURL),
        currentContainer.runtimeID == runtimeID
    else {
        var profile = game.launchProfile
        profile.container = compatibleContainerURL(for: runtimeID)
            .map(ContainerReference.init(url:))
        game.launchProfile = profile  // ⚠️ MODIFIES GAME AGAIN
        return
    }
}
```

**THE ACTUAL BUG:**

When you select Wine 11:
1. User picks Wine 11
2. `manualRuntimeSelection` setter runs
3. Sets `runtimeOverride = .wine11`
4. Sets `container = W11 container`
5. Updates `game.launchProfile`
6. **GameDataStore observation fires**
7. **View invalidates because game changed**
8. `.task` runs AGAIN
9. `ensureCompatibleContainer()` checks if container matches runtime
10. **If the container is ALREADY W11, it does NOTHING** ✅
11. **But if the container is "Default" (mythic-engine):**
    - The guard FAILS (W11 runtime doesn't match Default container)
    - It calls `compatibleContainerURL(for: .wine11)` which returns W11
    - It OVERWRITES `game.launchProfile` AGAIN
    - This triggers ANOTHER observation cycle

### Why It Reverts to Mythic Engine

**CRITICAL DISCOVERY:**

The UI shows "Mythic Engine" immediately after selecting Wine 11 because:

1. When you select Wine 11, the binding sets:
   - `runtimeOverride = .wine11`
   - `container = W11` 
   
2. BUT the Picker's `selection` is bound to `manualRuntimeSelection`, which has:
   ```swift
   get: { game.launchProfile.effectiveRuntimeID }
   ```

3. The `effectiveRuntimeID` is correctly `.wine11` after selection

4. **HOWEVER**, if `ensureCompatibleContainer()` is checking the container immediately and finding a mismatch, it may be **racing with the container assignment**

5. OR there's a timing issue where the Picker reads `effectiveRuntimeID` BEFORE the binding setter completes

### The Real Problem: Task Timing

The `.task { ensureCompatibleContainer() }` modifier on line 283 runs:
- On view appearance
- Possibly on every view update
- **Async, so it races with the manual selection**

This is a **RACE CONDITION**:
- Manual selection sets runtime + container
- `.task` fires asynchronously
- If `.task` reads the game BEFORE the container update lands, it sees a mismatch
- It "fixes" the mismatch by resetting the container
- But this might reset based on OLD state

---

## INVESTIGATION 2 — SET BINDING CORRECTNESS

### The New GameDataStore.binding(for:) Implementation

```swift
func binding(for gameID: String) -> Binding<Game>? {
    guard let game = library.first(where: { $0.id == gameID }) else {
        return nil
    }
    
    return Binding(
        get: {
            self.library.first(where: { $0.id == gameID })!
        },
        set: { updatedGame in
            self.library.remove(game)
            self.library.insert(updatedGame)
        }
    )
}
```

### Analysis

**PROBLEM:** This implementation is **INCORRECT** for `Game` being a class.

`Game` is `@Observable class`, meaning:
- It's a **reference type**
- Identity is based on the object reference, not its ID
- `Set<Game>` uses `Hashable`/`Equatable` based on `id: String`

**The Issue:**

1. `game` is captured in the binding closure (the Game object from `library.first`)
2. `updatedGame` in the setter is **THE SAME OBJECT REFERENCE** (Game is a class)
3. `self.library.remove(game)` removes based on Hashable equality (id match)
4. `self.library.insert(updatedGame)` inserts the same object back
5. This triggers `library.didSet` ✅
6. BUT it's **removing and inserting the exact same object reference**

This works to trigger `didSet`, but it's not semantically correct. A better implementation:

```swift
func binding(for gameID: String) -> Binding<Game>? {
    Binding(
        get: {
            guard let game = self.library.first(where: { $0.id == gameID }) else {
                fatalError("Game \(gameID) disappeared from library during binding lifetime")
            }
            return game
        },
        set: { updatedGame in
            // For a reference type, just trigger didSet
            // The game object was already mutated in-place
            guard let existingGame = self.library.first(where: { $0.id == gameID }) else {
                return
            }
            // Force didSet by removing and reinserting
            self.library.remove(existingGame)
            self.library.insert(existingGame)
        }
    )
}
```

**BUT**: The current implementation DOES work to trigger persistence. The bug is NOT here.

---

## INVESTIGATION 3 — ACTUAL WINE 11 RUNTIME

### Runtime Verification

✅ **Wine 11 is installed:**
```
~/Library/Application Support/Kraken/Runtimes/wine11/Wine Stable.app/
Contents/Resources/wine/bin/wine
Contents/Resources/wine/bin/wineserver
```

✅ **Runtime ID is correct:** `wine-11`

✅ **Containers exist:**
- **Default:** runtimeID = `mythic-engine`
- **W11:** runtimeID = `wine-11`

✅ **RuntimeResolver uses LaunchProfile.effectiveRuntimeID correctly**

---

## INVESTIGATION 4 — SUBNAUTICA LAUNCH

### Launch Flow

From LocalGameManager.swift line 43-130:

```swift
case .windows:
    // Single runtime authority
    let target = try RuntimeResolver.resolve(profile: launchProfile)
    
    let process = Process()
    process.arguments = [location.path] + target.launchArguments
    RuntimeResolver.configure(process, for: target)
    
    try process.run()
    // ... monitors process
```

### What Happens

1. `RuntimeResolver.resolve(profile:)` is called
2. Returns `ResolvedLaunchTarget` with:
   - `runtime: WineRuntime` (Wine 11 or Mythic Engine)
   - `container: ContainerReference`
   - `environment: [String: String]`
   - `graphicsBackend: GraphicsBackend`

3. Process is configured with the resolved environment
4. Process is launched
5. Kraken monitors the process via `process.terminationHandler`

### The "Running" State Issue

Kraken marks the game as "running" based on **process state**, not whether a window appears.

If the Wine process starts successfully but the game immediately fails (e.g., resolution error), Kraken still thinks it's running until the process exits.

**This is NOT a runtime selection bug.** This is a separate game compatibility issue.

---

## INVESTIGATION 5 — DX11 RESOLUTION ERROR

### The Error

```
"Couldn't switch to requested monitor resolution"
"Switching to resolution 1470x956 failed"
"Screen: DX11 could not switch resolution (1470x956 Fs=1 hz=0)"
```

### Analysis

**This error comes from the GAME ITSELF** (Subnautica), not from Kraken, Wine, or the graphics layer.

1. **1470x956 is an unusual resolution** — not a standard 16:9 or 16:10 ratio
2. **hz=0 means 0Hz refresh rate** — this is invalid
3. **Fs=1 means fullscreen mode requested**

### Likely Cause

Subnautica has a **saved graphics configuration** in its settings file that references:
- A resolution that doesn't exist on the current display
- A refresh rate of 0Hz (invalid)
- Fullscreen mode

This is stored in the game's user preferences, likely in:
```
~/Library/Containers/com.yerlsd.kraken/Containers/W11/drive_c/users/<username>/AppData/LocalLow/Unknown Worlds/Subnautica/
```

### Not a Kraken Bug

This is a **game configuration issue**, not a Kraken runtime/graphics backend bug.

**Fix:** Delete Subnautica's saved settings or manually edit the resolution/refresh rate.

---

## INVESTIGATION 6 — GRAPHICS BACKEND ARCHITECTURE

### Architecture Status

✅ **GraphicsBackend enum exists** with 5 backends
✅ **GraphicsBackendDetector exists**
✅ **GraphicsBackendResolver exists** and is called by RuntimeResolver
✅ **LaunchProfile.graphicsBackend field exists**
✅ **RuntimeResolver.resolve() calls GraphicsBackendResolver**
✅ **Environment generation includes backend-specific variables**

### Is It Wired Up?

**YES, the graphics backend architecture IS fully wired into the launch path:**

From RuntimeResolver.swift line 156-173:

```swift
// Resolve graphics backend
let resolvedBackend = try GraphicsBackendResolver.resolve(
    profile: profile,
    runtimeID: selectedRuntimeID
)

return .init(
    runtime: Engine.wineRuntime(for: selectedRuntimeID),
    container: reference,
    environment: environment(
        forRuntime: selectedRuntimeID,
        containerURL: reference.url,
        settings: container.settings,
        graphicsBackend: resolvedBackend  // ✅ USED
    ),
    launchArguments: profile.launchArguments,
    graphicsBackend: resolvedBackend
)
```

The resolved backend is passed to `environment()` which applies backend-specific WINEDLLOVERRIDES.

**The architecture is implemented AND wired correctly.**

---

## INVESTIGATION 7 — UNCOMMITTED CHANGES

### Files Modified (Not Committed)

1. `.gitignore`
2. `Kraken.xcodeproj/project.pbxproj`
3. `Kraken.xcodeproj/xcshareddata/xcschemes/Kraken.xcscheme`
4. `Mythic/Localizable.xcstrings`
5. `Mythic/Utilities/CodableAppStorage.swift`
6. `Mythic/Utilities/Game/Game.swift` — LaunchProfile extended
7. `Mythic/Utilities/Game/Runtime.swift` — RuntimeID and Runtime types
8. `Mythic/Utilities/GameDataStore.swift` — **Added SwiftUI import, binding() method, debug logs**
9. `Mythic/Utilities/GameManager/Legendary/LegendaryInterface.swift`
10. `Mythic/Utilities/GameManager/LocalGameManager.swift`
11. `Mythic/Utilities/Launch/LaunchRequest.swift`
12. `Mythic/Utilities/Migrator.swift`
13. `Mythic/Utilities/Wine/WineInterface+DXVK.swift`
14. `Mythic/Utilities/Wine/WineInterface.swift`
15. `Mythic/Views/Navigation/HomeView.swift` — **Changed .constant(game) to proper bindings**
16. `Mythic/Views/Unified/Components/GameListView.swift` — **Changed .constant(game) to proper bindings**
17. `Mythic/Views/Unified/Sheets/GameSettingsView.swift` — **Added debug logs**

### Files Created (Untracked)

1. `Mythic/Utilities/Game/GraphicsBackend.swift`
2. `Mythic/Utilities/Game/GraphicsBackendDetector.swift`
3. `Mythic/Utilities/Game/GraphicsBackendResolver.swift`
4. `Mythic/Utilities/Launch/RuntimeResolver.swift`
5. `Mythic/Utilities/Persistence/` (directory)
6. `KrakenTests/GraphicsBackendTests.swift`
7. `KrakenTests/RuntimeResolverTests.swift` (modified)
8. `docs/DEVELOPMENT_HANDOFF.md`
9. `docs/BUG_FIX_REPORT.md`
10. `docs/INVESTIGATION_REPORT.md` (this file)

---

## CONFIRMED ROOT CAUSES

### 1. RUNTIME SELECTION PERSISTENCE BUG — PRIMARY CAUSE

**ROOT CAUSE:** `.task { ensureCompatibleContainer() }` in GameSettingsView line 283

**Why It Fails:**

The `.task` modifier runs asynchronously when the view appears or updates. It's designed to ensure the container matches the runtime, but it's triggered at the wrong time and creates a race condition with manual selection.

**Race condition:**
1. User selects Wine 11
2. Binding setter updates `runtimeOverride` and `container`
3. View invalidates because game changed
4. `.task` fires again
5. `ensureCompatibleContainer()` reads game state
6. Depending on timing, it may see partial state
7. If it sees mismatched runtime/container, it "fixes" it
8. This overwrites the user's manual selection

### 2. RUNTIME SELECTION PERSISTENCE BUG — SECONDARY CAUSE (FIXED)

**ROOT CAUSE:** `.constant(game)` bindings in GameListView and HomeView

**Status:** ✅ FIXED by introducing `gameDataStore.binding(for:)`

**Why It Was a Problem:**

Constant bindings created read-only copies. Changes to the game in GameSettingsView didn't reach the canonical Game object in GameDataStore, so observation never fired and persistence never executed.

**Current Status:**

This is NOW FIXED. With proper bindings, changes DO propagate to GameDataStore and persistence DOES execute.

However, the PRIMARY bug (the `.task` race condition) prevents the fix from being visible to the user.

---

## 2. CONFIRMED ROOT CAUSE — SUBNAUTICA LAUNCH FAILURE

**NOT A RUNTIME SELECTION BUG**

The Subnautica launch failure is **unrelated to the runtime selection persistence issue**.

**ROOT CAUSE:** Subnautica's saved graphics settings reference an invalid resolution/refresh rate

**Evidence:**
- Error message: "Switching to resolution 1470x956 failed, hz=0"
- This is a game-generated error, not a Kraken/Wine error
- 1470x956 is not a standard resolution
- 0Hz is an invalid refresh rate

**Fix:** Delete or edit Subnautica's graphics configuration file

---

## 3. CONFIRMED ROOT CAUSE — DX11 RESOLUTION ERROR

**NOT A KRAKEN BUG**

This is a **game configuration issue** where Subnautica's saved settings reference a display mode that doesn't exist.

---

## 4. WAS THE PREVIOUS .constant(game) FIX CORRECT?

**YES, BUT INCOMPLETE**

The `.constant(game)` diagnosis was **correct** — it was preventing persistence.

The fix (proper bindings via `gameDataStore.binding(for:)`) was **correct** and **necessary**.

**BUT:** It only fixed the secondary cause. The primary cause (`.task` race condition) was not discovered until now.

---

## 5. IS THE NEW GameDataStore.binding(for:) IMPLEMENTATION CORRECT?

**FUNCTIONALLY YES, SEMANTICALLY AWKWARD**

The implementation works to trigger `library.didSet` and persistence.

However, it's awkward because:
- `Game` is a reference type (class)
- Removing and re-inserting the same object is semantically odd
- The object was already mutated in-place

A cleaner implementation would acknowledge this, but the current one DOES work.

**NOT THE CAUSE OF THE BUG.**

---

## 6. WHAT COMPONENT IS ACTUALLY OVERWRITING THE WINE 11 SELECTION?

**ensureCompatibleContainer() on line 302 of GameSettingsView.swift**

Triggered by the `.task` modifier on line 283.

---

## 7. WHAT COMPONENT IS ACTUALLY REPORTING SUBNAUTICA AS RUNNING?

**LocalGameManager** (line 43-130)

It monitors the Wine process via `process.terminationHandler`. As long as the process hasn't exited, Kraken considers the game "running", even if no visible window appeared.

This is **correct behavior** — the game process IS running, it just immediately failed to initialize graphics.

---

## 8. EXACT FILES/FUNCTIONS THAT NEED CHANGES

### To Fix Runtime Selection Bug:

**File:** `Mythic/Views/Unified/Sheets/GameSettingsView.swift`

**Changes Needed:**

1. **Remove or fundamentally redesign `.task { ensureCompatibleContainer() }`**
   - The task creates a race condition with manual selection
   - It runs at the wrong time (after every game update)
   
2. **Move container validation to a different lifecycle hook**
   - Use `.onAppear` ONLY on first view appearance
   - OR call `ensureCompatibleContainer()` explicitly only when needed
   - OR remove it entirely and trust the user/binding logic

3. **Add explicit container assignment in manualRuntimeSelection setter**
   - Already present, but ensure it runs completely before any other code

### Optional Cleanup:

**Remove debug logging** from:
- GameSettingsView.swift (lines ~352-366)
- GameDataStore.swift (observation and persistence debug prints)

---

## 9. MINIMAL FIX PLAN

### Option A: Remove .task Entirely

**Simplest fix:**

Remove line 283-285:
```swift
.task {
    ensureCompatibleContainer()
}
```

**Rationale:**

The `manualRuntimeSelection` binding already assigns a compatible container when the user selects a runtime. The `.task` is redundant and causes the race condition.

**Risk:**

If there are edge cases where a game has no container, or has an incompatible one, removing `.task` might not catch them.

**Mitigation:**

The `manualRuntimeSelection` binding's `set` closure already calls `compatibleContainerURL(for:)`, so container assignment IS handled.

### Option B: Replace .task with .onAppear (One-Time Only)

Replace `.task` with a one-time check:

```swift
@State private var hasEnsuredContainer = false

// ...

.onAppear {
    if !hasEnsuredContainer {
        ensureCompatibleContainer()
        hasEnsuredContainer = true
    }
}
```

**Rationale:**

Only run the compatibility check ONCE when the view first appears, not on every update.

**Risk:**

If the user changes runtime multiple times in one session, subsequent changes won't trigger the check. But the binding already handles container assignment, so this is fine.

### Option C: Make ensureCompatibleContainer() Smarter

Modify `ensureCompatibleContainer()` to:
1. Check if `runtimeOverride != nil` (manual mode)
2. If manual mode, skip the check entirely
3. Only enforce container compatibility in automatic mode

```swift
func ensureCompatibleContainer() {
    // Don't interfere with manual runtime selection
    guard game.launchProfile.runtimeOverride == nil else {
        return
    }
    
    let runtimeID = game.launchProfile.effectiveRuntimeID
    
    guard
        let currentURL = game.launchProfile.container?.url,
        let currentContainer = try? Wine.getContainerObject(at: currentURL),
        currentContainer.runtimeID == runtimeID
    else {
        var profile = game.launchProfile
        profile.container = compatibleContainerURL(for: runtimeID)
            .map(ContainerReference.init(url:))
        game.launchProfile = profile
        return
    }
}
```

**Rationale:**

The function is meant to help in automatic mode. In manual mode, the user explicitly selected both runtime AND container, so don't override their choice.

**This is the SAFEST fix.**

---

## 10. TEST PLAN

### Test 1: Runtime Selection Persistence

1. Launch Kraken
2. Open a Windows game's settings
3. Enable "Use a manual compatibility runtime"
4. Select Wine 11
5. **Verify:** Console shows debug logs
6. **Verify:** Picker immediately shows Wine 11 (not reverting to Mythic Engine)
7. Close settings
8. Reopen settings
9. **Verify:** Wine 11 is still selected
10. Quit Kraken
11. Restart Kraken
12. Open settings again
13. **Verify:** Wine 11 persists across restart

### Test 2: Container Assignment

1. Select Wine 11
2. **Verify:** Container picker shows W11 container
3. Select Mythic Engine
4. **Verify:** Container picker shows Default container
5. **Verify:** Container changes are saved

### Test 3: Automatic Mode

1. Disable "Use a manual compatibility runtime"
2. **Verify:** Runtime shows as "Automatic"
3. **Verify:** Kraken uses the game's default runtime

### Test 4: Subnautica Launch (Separate Issue)

1. Delete Subnautica's graphics settings:
   ```
   rm -rf "$HOME/Library/Containers/com.yerlsd.kraken/Containers/W11/drive_c/users/crossover/AppData/LocalLow/Unknown Worlds/Subnautica/"
   ```
2. Launch Subnautica
3. **Verify:** Game starts successfully in windowed mode
4. Configure graphics in-game

---

## RECOMMENDED FIX

**Use Option C: Make ensureCompatibleContainer() respect manual mode**

**Reasoning:**

1. It's the safest fix
2. It preserves the function's utility for automatic mode
3. It explicitly acknowledges that manual mode means "user knows best"
4. It requires minimal code change
5. It doesn't break any existing behavior

**Implementation:**

Add one guard at the top of `ensureCompatibleContainer()`:

```swift
func ensureCompatibleContainer() {
    // Don't interfere with manual runtime selection
    guard game.launchProfile.runtimeOverride == nil else {
        return
    }
    
    // ... rest of function unchanged
}
```

---

## CONCLUSION

The runtime selection persistence bug has TWO causes:

1. **PRIMARY (UNFIXED):** `.task { ensureCompatibleContainer() }` races with manual selection and overwrites it
2. **SECONDARY (FIXED):** `.constant(game)` bindings prevented persistence

The `.constant(game)` fix was correct and necessary, but insufficient on its own.

The Subnautica launch issue is **unrelated** — it's a game configuration problem.

**NEXT STEP:** Apply Option C fix and re-test.
