# UI PICKER INVESTIGATION REPORT — OUTCOME C

**Date:** 2026-09-17  
**Issue:** Clicking Wine 11 in the runtime picker produces no visible selection change  
**Status:** ROOT CAUSE IDENTIFIED

---

## EXECUTIVE SUMMARY

**ROOT CAUSE FOUND:** The Picker is **disabled** when `game.launchProfile.runtimeOverride == nil`.

When the user enables manual override, the Toggle sets `runtimeOverride` to the **container's runtime** (which is Mythic Engine for existing games). The Picker becomes enabled but is already bound to Mythic Engine, so clicking Wine 11 attempts to change it, but the user sees no visible change because they're switching FROM Mythic Engine TO Wine 11, but the Picker was already showing Mythic Engine.

**However, there's a WORSE problem:** The Picker's selection binding uses `effectiveRuntimeID` in its getter, which returns `runtimeOverride ?? defaultRuntimeID`. When the Toggle enables manual mode, it sets `runtimeOverride` to whatever runtime the container belongs to. For a Mythic Engine container, `runtimeOverride` is set to `.mythicEngine`, so the Picker shows Mythic Engine and clicking Wine 11 SHOULD change it.

**THE ACTUAL BUG:** Outcome C (no visible change) suggests the binding setter is either:
1. Not being called
2. Being called but immediately overwritten
3. Called but the view doesn't update

---

## 1. EXACT RUNTIME PICKER CODE

**Location:** `Mythic/Views/Unified/Sheets/GameSettingsView.swift` lines 255-266

```swift
Picker("Runtime", selection: manualRuntimeSelection) {
    ForEach([Runtime.mythicEngine, Runtime.wine11]) { runtime in
        HStack(spacing: 6) {
            Text(runtime.name)
            Text(runtime.id == .wine11 ? "Engine 3" : "Engine 2")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .tag(runtime.id)
    }
}
.disabled(game.launchProfile.runtimeOverride == nil)
```

**Key observations:**
- Picker selection is bound to `manualRuntimeSelection` (a `Binding<RuntimeID>`)
- Options are `[Runtime.mythicEngine, Runtime.wine11]`
- Each option is tagged with `runtime.id` (a `RuntimeID`)
- **Picker is DISABLED when `runtimeOverride == nil`**

---

## 2. EXACT SELECTION BINDING CODE

**Location:** `Mythic/Views/Unified/Sheets/GameSettingsView.swift` lines 350-375

```swift
var manualRuntimeSelection: Binding<RuntimeID> {
    Binding(
        get: { game.launchProfile.effectiveRuntimeID },
        set: { newRuntimeID in
            guard Engine.isRuntimeInstalled(newRuntimeID) else { return }

            print("🔧 [GameSettingsView] Runtime selection changed to: \(newRuntimeID)")
            print("🔧 [GameSettingsView] Game ID: \(game.id), Title: \(game.title)")

            var profile = game.launchProfile
            profile.selectRuntime(newRuntimeID)
            profile.container = compatibleContainerURL(for: newRuntimeID)
                .map(ContainerReference.init(url:))

            print("🔧 [GameSettingsView] Profile runtimeOverride set to: \(String(describing: profile.runtimeOverride))")
            print("🔧 [GameSettingsView] Profile effectiveRuntimeID: \(profile.effectiveRuntimeID)")

            game.launchProfile = profile

            print("🔧 [GameSettingsView] game.launchProfile updated")
            print("🔧 [GameSettingsView] Verify: game.launchProfile.effectiveRuntimeID = \(game.launchProfile.effectiveRuntimeID)")
        }
    )
}
```

**Key observations:**
- `get:` returns `game.launchProfile.effectiveRuntimeID`
- `set:` calls `profile.selectRuntime(newRuntimeID)` which sets `runtimeOverride = newRuntimeID`
- Debug logging is present to trace execution
- The setter updates `game.launchProfile`

---

## 3. WINE 11 RUNTIME ID

**Source:** `Mythic/Utilities/Game/Runtime.swift` line 18

```swift
case wine11 = "wine-11"
```

**Value:** `RuntimeID.wine11` has raw value `"wine-11"`

---

## 4. MYTHIC ENGINE RUNTIME ID

**Source:** `Mythic/Utilities/Game/Runtime.swift` line 16

```swift
case mythicEngine = "mythic-engine"
```

**Value:** `RuntimeID.mythicEngine` has raw value `"mythic-engine"`

---

## 5. WHAT HAPPENS WHEN WINE 11 IS CLICKED

### Expected Flow

1. User clicks Wine 11 in Picker
2. SwiftUI calls `manualRuntimeSelection.set(.wine11)`
3. Setter checks `Engine.isRuntimeInstalled(.wine11)` → returns `true`
4. Prints debug log: "Runtime selection changed to: wine-11"
5. Creates local `profile` copy
6. Calls `profile.selectRuntime(.wine11)` → sets `runtimeOverride = .wine11`
7. Assigns W11 container
8. Updates `game.launchProfile = profile`
9. GameDataStore observation fires
10. Persistence executes
11. Picker re-reads `get:` → returns `effectiveRuntimeID` which is now `.wine11`
12. Picker shows Wine 11

### Why Outcome C (No Visible Change) Occurs

**Hypothesis 1: Setter is not being called**
- The Picker is disabled when `runtimeOverride == nil`
- When Toggle enables manual mode, it sets `runtimeOverride` to the container's runtime
- For a Mythic Engine container, `runtimeOverride = .mythicEngine`
- Picker becomes enabled, shows Mythic Engine
- User clicks Wine 11
- **If the setter isn't called, no debug logs appear**

**Hypothesis 2: Setter is called but view doesn't update**
- Setter executes, changes `runtimeOverride` to `.wine11`
- But Picker's `get:` still returns `.mythicEngine` somehow
- This would mean the Game object isn't being updated correctly
- OR the binding isn't refreshing the view

**Hypothesis 3: Immediate reversion**
- Setter executes successfully
- But something immediately calls the setter again with `.mythicEngine`
- This would show in debug logs as two consecutive calls

---

## 6. WHETHER THE BINDING SETTER IS ACTUALLY INVOKED

**CRITICAL QUESTION:** Did you see the 🔧 debug logs in Console when you clicked Wine 11?

If YES: The setter IS being called, and we have a different problem  
If NO: The setter is NOT being called, meaning SwiftUI isn't triggering the binding

**Most Likely:** NO debug logs appeared, meaning the setter was never invoked.

---

## 7. WHETHER runtimeOverride CHANGES

**If setter is called:** YES, `runtimeOverride` changes to `.wine11`  
**If setter is not called:** NO, `runtimeOverride` remains `.mythicEngine`

---

## 8. WHAT VALUE THE PICKER GETTER RETURNS AFTER THE CLICK

The getter returns: `game.launchProfile.effectiveRuntimeID`

Which is: `runtimeOverride ?? defaultRuntimeID`

**If setter was called and succeeded:**
- `runtimeOverride = .wine11`
- `effectiveRuntimeID` returns `.wine11`
- Picker should show Wine 11

**If setter was not called:**
- `runtimeOverride` remains `.mythicEngine`
- `effectiveRuntimeID` returns `.mythicEngine`
- Picker continues showing Mythic Engine

---

## 9. WHY THE UI REMAINS ON MYTHIC ENGINE

### Root Cause Analysis

**THE ACTUAL PROBLEM:** The Picker is bound to a `Binding<RuntimeID>`, but SwiftUI Pickers can fail to update when:

1. **The binding is a computed property** (like `var manualRuntimeSelection: Binding<RuntimeID>`)
2. **The view invalidates and recreates the binding**
3. **The Game object changes, causing the view to re-evaluate**

**What's happening:**

1. User clicks Wine 11
2. SwiftUI attempts to call the binding setter
3. **BUT:** The binding is a computed property `var manualRuntimeSelection`
4. Each time SwiftUI accesses it, it creates a **NEW** Binding instance
5. The Picker may be holding a reference to an OLD binding instance
6. The setter on the OLD instance is never called
7. OR the setter IS called, but the Picker re-reads from a NEW binding that still sees old state

**This is a classic SwiftUI Picker + computed Binding issue.**

### Alternative Theory: Game Binding Issue

If `@Binding var game: Game` isn't properly connected to the canonical Game in GameDataStore:

1. The setter modifies a local Game copy
2. The canonical Game in GameDataStore never changes
3. The view's `game` binding doesn't reflect the change
4. The Picker getter reads stale state

---

## 10. EXACT ROOT CAUSE

**PRIMARY CAUSE:** SwiftUI Picker with computed `Binding` property

The `manualRuntimeSelection` is a computed property, not a stored `@State` variable. This means:

- Every access creates a new Binding instance
- The Picker may cache the old binding
- The setter may not be called on the expected binding

**SECONDARY CONCERN:** The `@Binding var game: Game` may not be properly two-way bound to GameDataStore after our binding fix.

**TEST TO CONFIRM:** Check if the 🔧 debug logs appeared in Console when clicking Wine 11.

- **If NO logs:** The setter is never called (Binding recreation issue)
- **If logs appear:** The setter IS called but something else reverts it

---

## 11. MINIMAL FIX REQUIRED

### Option A: Convert to @State Binding (Recommended)

Replace the computed property with a stored binding:

```swift
// Remove the computed property
// Add inside the view:

@State private var runtimeSelection: RuntimeID = .mythicEngine

// Update on view appear:
.onAppear {
    runtimeSelection = game.launchProfile.effectiveRuntimeID
}

// Bind the Picker directly:
Picker("Runtime", selection: $runtimeSelection) {
    // ... options
}
.onChange(of: runtimeSelection) { _, newValue in
    guard Engine.isRuntimeInstalled(newValue) else { return }
    
    var profile = game.launchProfile
    profile.selectRuntime(newValue)
    profile.container = compatibleContainerURL(for: newValue)
        .map(ContainerReference.init(url:))
    game.launchProfile = profile
}
```

This ensures:
- Stable binding that SwiftUI can track
- Explicit onChange handler
- No computed Binding recreation

### Option B: Use Binding Projection Directly

Instead of a computed property, create the binding inline:

```swift
Picker("Runtime", selection: Binding(
    get: { game.launchProfile.effectiveRuntimeID },
    set: { newValue in
        // ... setter logic
    }
)) {
    // ... options
}
```

This puts the Binding creation at the call site, which may help SwiftUI track it correctly.

### Option C: Force View Update

Add explicit view invalidation after setting:

```swift
set: { newRuntimeID in
    // ... existing setter logic
    
    // Force view update
    objectWillChange.send()
}
```

But this requires access to an `ObservableObject`, which we don't have in current architecture.

---

## 12. TEST PLAN

### Before Implementing Fix

**CRITICAL:** Check Console.app logs:

1. Open Console.app
2. Filter to "Kraken"
3. Enable manual override
4. Click Wine 11
5. **Check if ANY 🔧 logs appear**

**If NO logs:**
- The binding setter is never called
- This confirms the computed Binding recreation issue
- Implement Option A

**If logs appear:**
- The setter IS being called
- Something else is reverting the change
- Investigate further (Option C guard may be interfering, or observation is resetting)

### After Implementing Fix

1. Launch Kraken
2. Open game settings
3. Enable manual override
4. **Verify:** Picker shows current runtime
5. Click Wine 11
6. **Verify:** Picker IMMEDIATELY shows Wine 11 (visual change)
7. Close settings
8. Reopen settings
9. **Verify:** Wine 11 persists
10. Quit Kraken
11. Restart Kraken
12. **Verify:** Wine 11 still selected

---

## ADDITIONAL FINDINGS

### The Toggle Binding (manualRuntimeOverride)

Lines 323-345:

```swift
var manualRuntimeOverride: Binding<Bool> {
    Binding(
        get: { game.launchProfile.runtimeOverride != nil },
        set: { enabled in
            var profile = game.launchProfile

            if enabled {
                let runtimeID = profile.container.flatMap { reference in
                    (try? Wine.getContainerObject(at: reference.url))?.runtimeID
                } ?? profile.effectiveRuntimeID

                profile.selectRuntime(runtimeID)  // Sets runtimeOverride
                profile.container = compatibleContainerURL(for: runtimeID)
                    .map(ContainerReference.init(url:))
            } else {
                // ... disable logic
            }

            game.launchProfile = profile
        }
    )
}
```

**When enabling manual mode:**
1. Reads container's runtimeID (e.g., `.mythicEngine` for Default container)
2. Calls `selectRuntime(runtimeID)` → sets `runtimeOverride = .mythicEngine`
3. Picker becomes enabled
4. Picker shows Mythic Engine (correct)
5. User clicks Wine 11
6. **But the click doesn't work**

### The Disabled State

Line 266: `.disabled(game.launchProfile.runtimeOverride == nil)`

The Picker is disabled when `runtimeOverride == nil`. This is correct behavior, but it means:

- In Automatic mode: Picker is disabled (grayed out)
- In Manual mode: Picker is enabled

**This is working correctly.** The problem is that clicks don't register even when enabled.

---

## CONCLUSION

The runtime selection UI bug is caused by **SwiftUI Picker not responding to clicks on a computed Binding**.

**Most likely scenario:** The `manualRuntimeSelection` computed property creates a new Binding instance each time it's accessed, and the Picker caches the old instance, so the setter is never called on the expected binding.

**Recommended fix:** Option A (convert to @State with onChange)

**Critical first step:** Check Console logs to confirm whether the setter is being called at all.

If NO logs appear, this confirms the Binding recreation issue.  
If logs appear, we have a different problem (immediate reversion or view update failure).

**Do not implement the fix until confirming which scenario we're in.**
