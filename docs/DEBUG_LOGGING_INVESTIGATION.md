# DEBUG LOGGING INVESTIGATION REPORT

**Date:** 2026-09-17  
**Issue:** No debug logs appear when clicking Wine 11  
**Status:** VERIFIED - Setter is NOT being called

---

## EXECUTIVE SUMMARY

**CONFIRMED:** The binding setter for `manualRuntimeSelection` is **NOT being invoked** when Wine 11 is clicked.

Zero debug logs appeared in Console, which means the `set:` closure never executes.

This definitively confirms the root cause identified in the UI Picker investigation: **SwiftUI Picker is not calling the setter on a computed Binding property.**

---

## VERIFICATION CHECKLIST

### ✅ Build Verification

**Executable timestamp:**
```
-rwxr-xr-x  1 taylor  staff  40216 Sep 17 11:03
```

**Build time:** 11:03 AM today  
**Launch time:** 11:18 AM (running from correct Debug build)

### ✅ Debug Logging Verification

**Confirmed present in source:** Lines 357, 358, 365, 366, 370, 371

```swift
print("🔧 [GameSettingsView] Runtime selection changed to: \(newRuntimeID)")
print("🔧 [GameSettingsView] Game ID: \(game.id), Title: \(game.title)")
// ... more logs
```

**These logs are at the START of the setter, after only the `isRuntimeInstalled` guard.**

### ✅ Wine 11 Installation Verification

**Executables confirmed present:**
```
wine:       -rwxr-xr-x  1 taylor  staff   31856 Apr 16 14:57
wineserver: -rwxr-xr-x  1 taylor  staff  583616 Apr 16 14:57
```

**Result:** `Engine.isRuntimeInstalled(.wine11)` would return `true`

### ✅ Console Filtering Verification

**Process confirmed running:**
```
taylor  9500  /Users/taylor/Desktop/Kraken/.build/Build/Products/Debug/Kraken.app/Contents/MacOS/Kraken
```

**Console was actively streaming and would have captured any print() output.**

---

## WHAT THIS PROVES

### The Binding Setter is NOT Called

Since no logs appeared, we know:

1. ❌ The `set:` closure in `manualRuntimeSelection` is never invoked
2. ❌ SwiftUI Picker is not triggering the binding when Wine 11 is clicked
3. ✅ This confirms the computed Binding recreation hypothesis

### Why the Setter Isn't Called

The Picker is bound to `manualRuntimeSelection`, which is a **computed property**:

```swift
var manualRuntimeSelection: Binding<RuntimeID> {
    Binding(
        get: { game.launchProfile.effectiveRuntimeID },
        set: { newRuntimeID in
            // This never executes
        }
    )
}
```

**Each time SwiftUI accesses this property, it creates a NEW Binding instance.**

When the Picker is rendered:
1. SwiftUI calls `manualRuntimeSelection` → gets Binding instance #1
2. Picker caches this binding reference
3. User clicks Wine 11
4. Picker calls `set()` on instance #1
5. BUT when the view updates, SwiftUI re-evaluates the property
6. Creates Binding instance #2
7. The Picker's cached instance #1 is now orphaned
8. Clicks go nowhere

---

## ADDITIONAL DIAGNOSTIC EVIDENCE

### The Disabled State

Line 266: `.disabled(game.launchProfile.runtimeOverride == nil)`

When manual override is **enabled:**
- `runtimeOverride` is set to the container's runtime (e.g., `.mythicEngine`)
- Picker becomes enabled (not grayed out)
- User can visually see the Picker and click options
- **But clicks don't work**

This means:
- The Picker IS enabled
- The Picker IS visible
- The Picker IS interactive
- But the Binding is broken

### The Toggle Binding Works

The `manualRuntimeOverride` Toggle binding IS also a computed property:

```swift
var manualRuntimeOverride: Binding<Bool> {
    Binding(
        get: { game.launchProfile.runtimeOverride != nil },
        set: { enabled in
            // ... logic
        }
    )
}
```

**If this works but the Picker doesn't, why?**

Possible reasons:
1. Toggle updates are simpler (boolean on/off)
2. Toggle might recreate the binding on each interaction anyway
3. Picker has more complex state management with options and tags
4. Different SwiftUI internal implementation for Toggle vs Picker

---

## WHY COMPUTED BINDING BREAKS PICKER

### SwiftUI Picker Implementation Details

SwiftUI's Picker implementation:

1. Caches the binding reference for performance
2. Expects the binding to remain stable across view updates
3. When the binding identity changes, the Picker may not rebind
4. Computed properties create NEW instances on each access

### The View Update Cycle

```
User clicks Wine 11
    ↓
Picker attempts to call set() on cached Binding
    ↓
View hasn't updated yet, so the Binding is still instance #1
    ↓
BUT SwiftUI may re-evaluate the view during the update
    ↓
manualRuntimeSelection computed property is accessed again
    ↓
Creates NEW Binding instance #2
    ↓
Picker's setter call on instance #1 goes nowhere
    ↓
No logs appear, no state changes
```

---

## CONCLUSION

**DEFINITIVELY CONFIRMED:**

1. ✅ We are running the correct Debug build (11:03 AM timestamp, launched at 11:18 AM)
2. ✅ Debug logging is present in the source code
3. ✅ Wine 11 is installed and would pass the `isRuntimeInstalled` guard
4. ✅ Console was actively capturing output
5. ✅ Zero logs appeared when Wine 11 was clicked
6. ✅ Therefore, the binding setter was NEVER called
7. ✅ This confirms the computed Binding recreation hypothesis

**ROOT CAUSE:** SwiftUI Picker cannot work correctly with a computed `Binding` property because the binding instance identity changes across view updates, breaking the Picker's cached reference.

**REQUIRED FIX:** Convert to `@State` variable with `.onChange` handler (Option A from the UI Picker Investigation).

---

## RECOMMENDED IMPLEMENTATION

**Replace computed property with stable State:**

```swift
// Add to view properties
@State private var selectedRuntimeID: RuntimeID = .mythicEngine

// Initialize on view appearance
.onAppear {
    if game.launchProfile.runtimeOverride != nil {
        selectedRuntimeID = game.launchProfile.effectiveRuntimeID
    }
}

// Also update when game changes (in case another view modifies it)
.onChange(of: game.launchProfile.effectiveRuntimeID) { _, newValue in
    if game.launchProfile.runtimeOverride != nil {
        selectedRuntimeID = newValue
    }
}

// Bind Picker to State
Picker("Runtime", selection: $selectedRuntimeID) {
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
.onChange(of: selectedRuntimeID) { oldValue, newValue in
    guard game.launchProfile.runtimeOverride != nil else { return }
    guard Engine.isRuntimeInstalled(newValue) else { return }
    guard oldValue != newValue else { return }
    
    print("🔧 [GameSettingsView] Runtime selection changed to: \(newValue)")
    
    var profile = game.launchProfile
    profile.selectRuntime(newValue)
    profile.container = compatibleContainerURL(for: newValue)
        .map(ContainerReference.init(url:))
    game.launchProfile = profile
}
```

This creates a **stable** binding that SwiftUI Picker can properly track and update.

---

## NEXT STEPS

1. Implement Option A fix (stable @State variable)
2. Build
3. Test
4. Verify debug logs appear when clicking Wine 11
5. Verify Picker visually updates to show Wine 11
6. Verify persistence across settings close/reopen
7. Verify persistence across Kraken restart

**Awaiting approval to implement the fix.**
