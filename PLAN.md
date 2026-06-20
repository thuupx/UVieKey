# UVieKey App Layer — Implementation Plan

> **Goal:** Build a production-quality macOS Vietnamese IME app wrapping the `uvie-rs` Rust engine.
>
> **Status:** Foundation + Smart Switch Key COMPLETED. Core features IN PROGRESS.

---

## Architecture

```
UVieKey (SwiftUI + AppKit)
├── App/
│   └── UVieKeyApp.swift              # @main, AppDelegate, LSUIElement
├── Core/
│   ├── EngineBridge.swift            # FFI to uvie-rs (C ABI)
│   ├── EventTap.swift               # CGEventTap + backspace-replacement
│   └── TextDiff.swift               # Compute backspace + suffix diff
├── Features/
│   ├── InputMethodManager.swift      # VN/EN toggle, per-app state
│   ├── SmartSwitchManager.swift     # [COMPLETED] NSUserDefaults persistence
│   └── MacroManager.swift           # [PENDING] Text expansion
├── UI/
│   ├── MenuBarController.swift        # Status bar icon + menu
│   ├── SettingsWindow.swift          # SwiftUI preferences
│   └── OnboardingView.swift         # First-launch permission flow
└── Utils/
    ├── AccessibilityChecker.swift    # Permission helper
    └── Defaults.swift                # UserDefaults key constants
```

---

## Phase-by-Phase Implementation

### Phase A: Foundation **[COMPLETED]**

**Deliverables:**
- Project structure (`Package.swift`, `Sources/`, `build.sh`)
- `EngineBridge.swift` — FFI wrapper with `@_silgen_name` imports
- `EventTap.swift` — CGEventTap with synthetic event tagging
- `TextDiff.swift` — Compute backspace count + new suffix
- `MenuBarController.swift` — V/E icon, toggle, quit
- `SettingsWindow.swift` — SwiftUI preferences panel
- `OnboardingView.swift` — Accessibility permission flow
- `Info.plist` — `LSUIElement = true` (menu bar only)
- `UVieKey.entitlements` — No sandbox (required for Accessibility)

**Design decisions:**
- **Backspace-replacement trick** instead of command-style (avoids `_syncKey`)
- **Synthetic event tag** (`0x55564945`) to avoid processing own output
- **Dedicated tap thread** with `CFRunLoop` for latency

---

### Phase B: Smart Switch Key **[COMPLETED]**

**Feature:** Remember Vietnamese/English state per application.

**Implementation:**
- `SmartSwitchManager.swift` — JSON-backed map `[bundleID: Int]`
- `InputMethodManager.swift` — Wires app-switch notification → restore state
- Legacy OpenKey binary format migration support

**Persistence format:**
```json
{"com.apple.Safari": 1, "com.microsoft.VSCode": 0}
```
Lower bit = language (0=EN, 1=VN), upper bits = codeTable.

---

### Phase C: Macro System **[PENDING]**

**Feature:** Text expansion (e.g. `btw` → `by the way`).

**Design:**
- App layer tracks raw keystrokes in a separate `macroBuffer` (not engine buffer)
- On break character (space, comma, period, Enter), check if `macroBuffer` matches a dictionary key
- If match: send N Backspaces + expansion text, then clear `macroBuffer`
- If no match: pass break char to engine normally

**Data model:**
```swift
struct MacroEntry {
    let abbreviation: String
    let expansion: String
}
```

**Storage:** `~/Library/Application Support/UVieKey/macros.json`

**UI:** Settings panel with add/remove/edit table.

**Est. effort:** ~150 lines, 3–4 hours.

---

### Phase D: Uppercase First Character **[PENDING]**

**Feature:** Auto-capitalize first letter after `. ` or Enter/Return.

**Implementation:**
- `EventTap` tracks punctuation + space in a small state machine
- On next alphabetic key: inject `Shift` modifier into synthetic event instead of lowercase char
- Must not interfere with engine's composing state

**Edge cases:**
- After `...` (ellipsis) should still capitalize
- After `Enter` without `.` (new paragraph)
- User types Shift+Letter manually → respect user intent

**Est. effort:** ~40 lines, 1–2 hours.

---

### Phase E: Browser Compatibility Fixes **[PENDING]**

**Feature:** Work around browser autocomplete / suggestion dropdown.

**Problem:** When engine sends Backspace + new Unicode string, browsers (Chrome, Safari) may show stale autocomplete dropdown.

**Solutions:**
1. **Empty Unicode sentinel** — Send `0x202F` (narrow no-break space) before backspace to invalidate autocomplete
2. **App-specific list** — Maintain `Set<String>` of bundle IDs needing special handling
3. **Shift+Left Arrow select** — For Chromium browsers, select previous char before overwriting

**Files to modify:** `EventTap.swift` — add `BrowserCompatibility` helper

**Est. effort:** ~30 lines, 1–2 hours.

---

### Phase F: Other Language Detection **[PENDING]**

**Feature:** Auto-disable Vietnamese input when keyboard layout is not English.

**Implementation:**
```swift
import Carbon
let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
let languages = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages)
```

If current language does not start with `"en"`, bypass engine (pass-through).

**Est. effort:** ~15 lines, 30 min.

---

### Phase G: Update Checker **[PENDING]**

**Feature:** Check for new versions from GitHub releases.

**Implementation:**
- `URLSession` HTTP GET to GitHub API
- Parse SemVer from latest release tag
- Compare with bundled version (`CFBundleShortVersionString`)
- If newer: show notification with "Download" / "Later" buttons

**Est. effort:** ~50 lines, 1–2 hours.

---

### Phase H: Accessibility & Polish **[PENDING]**

**Feature:** Production readiness.

**Checklist:**
- [ ] Code signing + Notarization (Xcode project export)
- [ ] Sparkle framework for auto-update (alternative to Phase G)
- [ ] VoiceOver labels for menu bar icon
- [ ] High-contrast mode support
- [ ] Reduced motion support
- [ ] Crash reporting (e.g. Sentry, or roll your own)
- [ ] Localized strings (Vietnamese + English)

---

## Current File Inventory

```
UVieKey/
├── Package.swift
├── Info.plist
├── UVieKey.entitlements
├── build.sh
├── README.md
├── PLAN_APP.md (this file)
└── Sources/UVieKey/
    ├── App/
    │   └── UVieKeyApp.swift
    ├── Core/
    │   ├── EngineBridge.swift
    │   ├── EventTap.swift
    │   └── TextDiff.swift
    ├── Features/
    │   ├── InputMethodManager.swift
    │   ├── SmartSwitchManager.swift
    │   └── MacroManager.swift (PENDING)
    ├── UI/
    │   ├── MenuBarController.swift
    │   ├── SettingsWindow.swift
    │   └── OnboardingView.swift
    └── Utils/
        ├── AccessibilityChecker.swift
        └── Defaults.swift
```

---

## Priority Queue

| Priority | Phase | Feature | Est. Effort |
|----------|-------|---------|-------------|
| P1 | C | Macro System | 3–4 hrs |
| P2 | D | Uppercase First Character | 1–2 hrs |
| P3 | E | Browser Compatibility | 1–2 hrs |
| P4 | F | Other Language Detection | 30 min |
| P5 | G | Update Checker | 1–2 hrs |
| P6 | H | Accessibility & Polish | 2–3 hrs |

---

## Acceptance Criteria

| # | Criterion | How Verified |
|---|-----------|--------------|
| 1 | App launches without crash | Manual launch |
| 2 | Menu bar icon shows V/E | Visual |
| 3 | Toggle VN/EN works | Click menu / hotkey |
| 4 | Smart Switch remembers per app | Switch between 2 apps |
| 5 | Backspace-replacement works | Type Vietnamese text |
| 6 | Settings persist after relaunch | Restart app |
| 7 | Onboarding shows if no Accessibility | Delete permission, relaunch |
| 8 | Build succeeds (`./build.sh`) | CI / Manual |

---

*Plan version: 1.0*
*Last updated: 2026-06-11*
