# KRAKEN DEVELOPMENT HANDOFF

**Date:** 2026-09-17  
**Branch:** `engine3/wine11`  
**Status:** Runtime selection bug FIXED, ready for manual verification

---

## PROJECT STATUS

### Build Status
✅ **SUCCESS** - Clean Debug build  
✅ **TESTS PASSING** - All 50 tests pass (exit code 0)

### Current Branch
```
engine3/wine11
```

**Working tree:** Modified, not committed  
**Pre-existing stash:** Untouched, preserved

---

## PRIORITY 6 — WINE 11 RUNTIME SELECTION BUG — FIXED ✅

### Root Cause Identified

The runtime selection persistence bug was caused by **constant game bindings** throughout the view hierarchy.

**The Problem:**
- `GameListView` and `HomeView` used `.constant(game)` bindings
- These create **read-only bindings** that cannot propagate changes back
- When `GameSettingsView` modified `game.launchProfile`, it modified a local copy
- The actual `Game` in `GameDataStore.shared.library` was never touched
- Observation never fired, persistence never executed, changes were lost

### The Fix

**1. Added binding helper to GameDataStore:**
```swift
func binding(for gameID: String) -> Binding<Game>?
```
This creates proper two-way bindings to games in the library Set.

**2. Updated view bindings:**
- `GameListView`: replaced `.constant(game)` with `gameDataStore.binding(for: game.id)`
- `HomeView`: same replacement
- Now changes propagate to the actual library Game objects

**3. Added temporary debug logging:**
- GameSettingsView runtime selection
- GameDataStore observation callbacks
- GameDataStore persistence execution

### Files Changed
- `Mythic/Utilities/GameDataStore.swift` - Added SwiftUI import and binding helper
- `Mythic/Views/Unified/Components/GameListView.swift` - Proper bindings
- `Mythic/Views/Navigation/HomeView.swift` - Proper bindings  
- `Mythic/Views/Unified/Sheets/GameSettingsView.swift` - Debug logging

### Build & Test Results
```
✅ BUILD SUCCEEDED
✅ ALL TESTS PASSING (50/50)
```

### Manual Verification Required

The fix is architecturally correct and tests pass, but the full UI flow must be verified:

1. Launch Kraken
2. Open game settings
3. Enable manual compatibility override
4. Select Wine 11
5. Verify console shows debug logs (🔧 and 💾 messages)
6. Close and reopen settings - Wine 11 should remain selected
7. Quit and restart Kraken - Wine 11 should still be selected
8. Verify container selection persists
9. Verify changing to Mythic Engine works and persists
10. Verify Automatic selection works

### Cleanup After Verification

Remove debug logging from:
- `GameSettingsView.swift` - All `print("🔧 ...")` statements
- `GameDataStore.swift` - All `print("💾 ...")` statements

---

## PRIORITY 6 — WINE 11 GRAPHICS BACKEND IMPLEMENTATION

### ✅ COMPLETED WORK

#### Architecture Implemented
- **GraphicsBackend enum:** 5 backends (automatic, d3dmetal, dxmt, dxvk, wined3d)
- **GraphicsBackendCapabilities:** DirectX 9/10/11/12 support tracking per backend
- **Per-game storage:** LaunchProfile extended with `graphicsBackend` and `lastSuccessfulBackend` fields
- **Backend detection:** GraphicsBackendDetector checks runtime-specific availability
- **Backend resolution:** GraphicsBackendResolver with deterministic resolution order
- **Environment generation:** Backend-specific WINEDLLOVERRIDES and DYLD paths
- **RuntimeResolver integration:** Backend resolution integrated into launch path
- **Backward compatibility:** Older games default to `.automatic` backend

#### Files Created
```
Mythic/Utilities/Game/GraphicsBackend.swift
Mythic/Utilities/Game/GraphicsBackendDetector.swift
Mythic/Utilities/Game/GraphicsBackendResolver.swift
KrakenTests/GraphicsBackendTests.swift
```

#### Files Modified
```
Mythic/Utilities/Game/Game.swift - LaunchProfile extended
Mythic/Utilities/Launch/RuntimeResolver.swift - Backend integration
KrakenTests/RuntimeResolverTests.swift - Fixed test calls
Kraken.xcodeproj/project.pbxproj - Added new files
```

#### Test Coverage
- GraphicsBackendTests: 13/13 passed
- RuntimeResolverTests: 16/16 passed
- LaunchProfileMergeTests: 13/13 passed
- PersistenceTests: 8/8 passed

### ⚠️ REMAINING WORK

#### 1. D3DMETAL INTEGRATION
- **Status:** Not started
- **Resource:** `~/Documents/Game Porting Toolkit 4.0/Evaluation environment for Windows games 4.0 beta 2.dmg`
- **Tasks:**
  - Deploy GPTK 4.0 beta 2 payload into Wine 11 runtime
  - Install D3DMetal.framework
  - Verify D3D device initialization

#### 2. DXVK FOR WINE 11
- **Status:** Not started
- **Tasks:**
  - Install DXVK DLLs in Wine 11 runtime
  - Update detection to support Wine 11 (currently returns false)
  - Verify DXVK actually works with Wine 11

#### 3. DXMT VERIFICATION
- **Status:** Not started
- **Tasks:**
  - Verify Gcenx Wine 11.0 DXMT compatibility
  - Test actual DXMT functionality
  - Update detection if needed

#### 4. LAUNCH PATH INTEGRATION
- **Status:** Not started
- **Tasks:**
  - Wire LocalGameManager to record successful backend
  - Wire LegendaryInterface to record successful backend
  - Test backend feedback loop

---

## BUILD & TEST COMMANDS

### Build Debug
```bash
cd ~/Desktop/Kraken
xcodebuild \
  -project Kraken.xcodeproj \
  -scheme Kraken \
  -configuration Debug \
  -derivedDataPath ~/Desktop/Kraken/.build \
  CODE_SIGNING_ALLOWED=NO \
  SWIFTLINT=NO \
  -parallel-testing-enabled YES \
  -jobs $(sysctl -n hw.ncpu)
```

### Run Tests
```bash
cd ~/Desktop/Kraken
xcodebuild \
  -project Kraken.xcodeproj \
  -scheme Kraken \
  -derivedDataPath ~/Desktop/Kraken/.build \
  CODE_SIGNING_ALLOWED=NO \
  SWIFTLINT=NO \
  -parallel-testing-enabled YES \
  -jobs $(sysctl -n hw.ncpu) \
  test
```

### Launch Kraken with Console
```bash
cd ~/Desktop/Kraken
open -a Console  # to see debug logs
open .build/Build/Products/Debug/Kraken.app
```

---

## ENGINEERING CONSTRAINTS

### Must Preserve
- ✅ Existing working-tree changes
- ✅ Pre-existing stash (do not modify/drop)
- ✅ Branch: `engine3/wine11`
- ✅ Engine 2 unchanged
- ✅ Existing Wine 11 runtime unchanged
- ✅ W11 container unchanged
- ✅ No commits, no push, no reset, no clean

### Architecture Rules
- **Single runtime authority:** RuntimeResolver is the only resolver
- **No silent fallback:** Explicit backend choice must fail if unavailable, not substitute
- **Per-game isolation:** Backend/runtime selection is per-game via LaunchProfile
- **Process-scoped environment:** WINEDLLOVERRIDES per process, not global
- **Backward compatibility:** Old games default to .automatic backend

### Concurrency Model
- Game is `@Observable` (Swift Observation framework)
- GameDataStore is `@MainActor`
- Do not introduce manual `@Published` or Combine publishers
- Preserve existing observation tracking architecture

---

## VERIFIED FACTS

### GPTK 4.0 Beta 2
- **Location:** `~/Documents/Game Porting Toolkit 4.0/Evaluation environment for Windows games 4.0 beta 2.dmg`
- **Version:** 4.0 beta 2
- **D3DMetal:** 4.0b2
- **Status:** Not yet deployed into Wine 11 runtime

### Wine 11 Runtime
- **Path:** `~/Library/Application Support/Kraken/Runtimes/wine11/Wine Stable.app/`
- **Executable:** `Contents/Resources/wine/bin/wine`
- **Version:** wine-11.0 (Gcenx build)
- **Status:** Verified working

### Wine 11 Container
- **Path:** `~/Library/Containers/com.yerlsd.kraken/Containers/W11/`
- **Runtime ID:** wine-11
- **Status:** Verified working

---

## NEXT SESSION START HERE

**TASK 1:** Manual verification of runtime selection persistence fix

1. Launch Kraken with Console.app open
2. Navigate to a game's settings
3. Enable manual compatibility override
4. Select Wine 11
5. Verify debug logs appear in console
6. Test persistence across settings close/reopen
7. Test persistence across Kraken restart
8. Verify container selection persists
9. Test switching back to Mythic Engine
10. Test Automatic selection

**TASK 2:** If verification succeeds, remove debug logging

**TASK 3:** Commit the runtime selection fix

**TASK 4:** Continue with Wine 11 backend work (D3DMetal, DXVK, DXMT)

---

## KNOWN WARNINGS (Not Blockers)

### Xcode Build Warnings
- SwiftLint not installed (expected)
- Test files in Copy Bundle Resources (phantom warning)
- VariableManager deprecated (unrelated to current work)
- Unstructured throwing tasks (unrelated to current work)
- LocalGameManager concurrency warnings (unrelated to current work)

These warnings pre-exist and do not block Wine 11 work.

---

## REFERENCE DOCUMENTS

- **docs/BUG_FIX_REPORT.md** - Detailed analysis of runtime selection bug and fix
- **docs/DEVELOPMENT_HANDOFF.md** - This document

---

## ENGINEERING NOTES

### The Binding Bug Pattern

This bug demonstrates a common SwiftUI pitfall:

**❌ WRONG:**
```swift
ForEach(computedArray) { item in
    ItemView(item: .constant(item))
}
```

**✅ CORRECT:**
```swift
ForEach(computedArray) { item in
    if let binding = dataStore.binding(for: item.id) {
        ItemView(item: binding)
    }
}
```

When iterating over computed collections, always bind to the canonical source, not copies.

### Why Remove/Insert Works

The binding helper uses:
```swift
self.library.remove(game)
self.library.insert(updatedGame)
```

This is necessary because:
- `Game` is a class (reference type)
- `library` is a `Set<Game>`
- Mutating a class in-place doesn't trigger Set's `didSet`
- Remove/insert ensures `didSet` fires
- This triggers persistence and observation

---

## PRIORITY ORDER

1. ✅ Runtime selection persistence bug - **FIXED**
2. ⚠️ Manual verification of the fix
3. ⚠️ D3DMetal GPTK 4 integration
4. ⚠️ DXVK Wine 11 integration
5. ⚠️ DXMT verification
6. ⚠️ Launch path backend recording
7. ⚠️ UI/UX overhaul (after Wine 11 is functional)

---

**End of handoff**
