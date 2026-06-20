# App-Layer Features Reference

> **Scope:** All features that belong to the **platform-specific application** (macOS/Windows/Linux UI), not the core Vietnamese text-processing engine.
>
> The engine (`uvie-rs`) is a pure text-processing library. Everything in this document is implemented in the **host app** that wraps the engine.

---

## Table of Contents

1. [Input Method Management](#1-input-method-management)
2. [Smart Features](#2-smart-features)
3. [Macro System](#3-macro-system)
4. [UI / UX Features](#4-ui--ux-features)
5. [Platform Integration (macOS)](#5-platform-integration-macos)
6. [Advanced Engine Options](#6-advanced-engine-options)
7. [Quick Input Shortcuts](#7-quick-input-shortcuts)
8. [Pending / Future Ideas](#8-pending--future-ideas)

---

## 1. Input Method Management

### 1.1 Toggle Input Method

- **Description:** Switch between Vietnamese and English mode.
- **Trigger:** Configurable hotkey (default `Cmd` on macOS, `Alt` on Win/Linux).
- **Engine API:** `uvie_engine_set_input_method()` / `uvie_engine_get_input_method()`
- **State persistence:** Save `vLanguage` to user preferences.

### 1.2 Per-App Language Memory (Smart Switch Key)

- **Description:** Remember which input method (Vietnamese/English) was last used in each application. Automatically restore when switching back to that app.
- **Data model:** `Map<BundleID/String, Int8>` — maps app identifier → `(language | codeTable)`.
- **macOS API:** `NSWorkspace.shared.frontmostApplication.bundleIdentifier`
- **Save/Load:** Serialize to `NSUserDefaults` / Registry / XDG config.
- **Engine impact:** None. App layer sets engine input method before feeding keys.

### 1.3 Remember Code Table per App

- **Description:** Remember which output code table (Unicode / TCVN3 / VNI / Unicode Compound) was used per app.
- **Data model:** Same as Smart Switch Key, higher bits store `codeTable`.

### 1.4 Temporarily Disable Engine

- **Description:** Hotkey to instantly bypass the engine (pass-through all keystrokes).
- **Trigger:** Configurable hotkey (default `Command` on macOS, `Alt` on Windows/Linux).
- **Implementation:** App sets a `bypass` flag. When active, all intercepted keys are sent directly to OS without entering the engine.
- **Engine impact:** None. App layer decision.

---

## 2. Smart Features

### 2.1 Upper Case First Character

- **Description:** Automatically capitalize the first letter of a sentence after punctuation (`.`, `?`, `!`) or Enter/Return.
- **Trigger:** Detect punctuation + space / newline in the output stream.
- **Implementation:** App layer tracks sentence boundaries. On next alphabetic key, inject Shift modifier into the synthetic event.
- **Edge case:** Must not interfere with engine's composing state.

### 2.2 Fix Browser Autocomplete

- **Description:** Prevent browser autocomplete/suggestion from interfering with backspace-replacement.
- **Why needed:** When engine sends Backspace + new Unicode string, browsers may show stale autocomplete dropdown.
- **Workarounds:**
  - Send an empty Unicode character (`0x202F`) before backspace to invalidate autocomplete.
  - For Chromium browsers: use Shift+Left Arrow to select the previous character before overwriting.
- **App-specific list:** Maintain `NSArray` / vector of bundle IDs that need special handling.

### 2.3 Other Language Detection

- **Description:** Automatically disable Vietnamese input when the current keyboard layout is not English.
- **macOS API:** `TISCopyCurrentKeyboardInputSource` → `kTISPropertyInputSourceLanguages`
- **Implementation:** Check if current language starts with `"en"`. If not, pass-through all keys.

---

## 3. Macro System

### 3.1 Text Expansion (Macro)

- **Description:** Expand short abbreviations into full phrases.
- **Examples:**
  - `btw` → `by the way`
  - `asap` → `as soon as possible`
  - `omw` → `on my way`
- **Trigger characters:** Space, comma, period, Enter, Return, semicolon, etc. (configurable break characters).
- **Data model:** `Map<String, String>` — abbreviation → expansion.
- **Auto-capitalization:**
  - `Btw` → `By the way`
  - `BTW` → `BY THE WAY`
- **Engine vs App:** The engine can track macro keys, but the **dictionary and expansion logic** belong to the app.
- **Implementation flow:**

  ```text
  1. App tracks raw keystrokes in a separate buffer.
  2. When break character detected, check if buffer matches a macro key.
  3. If match: send N Backspaces (N = macro key length), then send expansion text.
  4. If not match: let engine process normally.
  ```

### 3.2 Macro in English Mode

- **Description:** Allow macro expansion even when Vietnamese mode is off.
- **Use case:** Type `btw` in English mode, still expands to `by the way`.

### 3.3 Macro Persistence

- **Description:** Save/load macro dictionary from user preferences.
- **macOS:** `NSUserDefaults` with custom plist structure.
- **Format:** Binary blob or JSON array of `[abbreviation, expansion]` pairs.

---

## 4. UI / UX Features

### 4.1 System Tray / Menu Bar Icon

- **Description:** Show app icon in system tray / menu bar for quick access.
- **Features:**
  - Toggle Vietnamese/English
  - Open settings
  - Show current input method status
  - Exit app

### 4.2 Settings Panel

- **Description:** GUI for configuring all engine and app-layer options.
- **macOS:** SwiftUI / AppKit preferences window.
- **Settings categories:**
  - Input method (Telex / VNI)
  - Code table (Unicode / TCVN3 / VNI / Unicode Compound)
  - Spelling options
  - Quick input options
  - Macro editor
  - Hotkey configuration
  - Smart switch settings

### 4.3 Visual Feedback

- **Description:** Audio or visual cue when switching input methods.
- **Options:**
  - System beep (`NSBeep()`)
  - OSD (On-Screen Display) overlay
  - Menu bar icon color change

### 4.4 Onboarding / Permission Prompt

- **Description:** Guide user to grant Accessibility permission (required for CGEventTap).
- **macOS flow:**
  1. Detect if Accessibility is granted.
  2. If not, show dialog explaining why it's needed.
  3. Open System Settings → Privacy & Security → Accessibility.
  4. Poll with exponential backoff until granted.

---

## 5. Platform Integration (macOS)

### 5.1 CGEventTap Keystroke Interception

- **Description:** Global keyboard hook to intercept and modify keystrokes system-wide.
- **API:** `CGEventTapCreate` with `kCGSessionEventTap` or `kCGAnnotatedSessionEventTap`.
- **Requirements:** Accessibility permission.
- **Thread model:** Dedicated thread with `CFRunLoop`.
- **Synthetic event tagging:** Mark self-generated events with a custom tag (`0x55564945` = "UVIE") to avoid processing own output.

### 5.2 Backspace-Replacement Trick

- **Description:** Core UX pattern for composing input.
- **Flow:**

  ```text
  1. Intercept key event.
  2. Feed key to engine.
  3. Compare old_composing vs new_composing.
  4. Compute diff (common prefix length).
  5. Send Backspace (N times) to delete old suffix.
  6. Send Unicode string of new suffix.
  7. Suppress original key event.
  ```

- **Advantage over command-style:** No need to sync `_syncKey` for multi-byte characters.

### 5.3 Active App Detection

- **Description:** Track which app currently has focus for Smart Switch Key.
- **macOS API:** `NSWorkspace.sharedWorkspace.frontmostApplication`
- **Notification:** `NSWorkspace.didActivateApplicationNotification`

### 5.4 Update Checker

- **Description:** Check for new versions from GitHub releases or custom server.
- **Implementation:** `URLSession` HTTP request → parse SemVer → compare with bundled version.

---

## 6. Advanced Engine Options

These are **configuration flags** passed to the engine, but the UI to toggle them is app-layer.

### 6.1 Spelling Check (`vCheckSpelling`)

- **Description:** Validate Vietnamese phonotactics while typing.
- **Engine behavior:** If invalid, fallback to raw input.
- **App UI:** Checkbox in settings.

### 6.2 Restore If Wrong Spelling (`vRestoreIfWrongSpelling`)

- **Description:** If spelling check rejects a word, restore all previously typed keys to their literal form.
- **Engine behavior:** Reset composing and replay raw keystrokes.

### 6.3 Modern Orthography (`vUseModernOrthography`)

- **Description:** Use `oà`, `uý` style instead of traditional `òa`, `úy`.
- **Engine impact:** Changes tone placement rules for certain vowel pairs.

### 6.4 Free Mark (`vFreeMark`)

- **Description:** Allow placing tone marks on any vowel, not just the "correct" one according to Vietnamese rules.
- **Use case:** Typing poetry or non-standard words.
- **Engine impact:** Tone placement ignores vowel hierarchy rules.

### 6.5 Allow Consonant Z/F/W/J (`vAllowConsonantZFWJ`)

- **Description:** Treat `z`, `f`, `w`, `j` as valid consonants in spelling check.
- **Use case:** Quick Start Consonant feature — `j` acts as `gi`, `f` as `ph`, etc.

### 6.6 Temporarily Disable Spelling (`vTempOffSpelling`)

- **Description:** Hotkey to toggle spelling check on/off mid-session.
- **Trigger:** Ctrl key (configurable).
- **App layer:** Detect modifier change, toggle engine flag.

---

## 7. Quick Input Shortcuts

### 7.1 Quick Start Consonant (`vQuickStartConsonant`)

- **Description:** Type single-letter shortcuts for common consonant clusters.
- **Mappings:**
  - `j` → `gi`
  - `f` → `ph`
  - `w` → `qu`
- **Engine API:** `uvie_engine_set_quick_start(enabled)`
- **Use case:** Faster typing for common clusters.

### 7.2 Quick End Consonant (`vQuickEndConsonant`)

- **Description:** Single-letter shortcuts for ending consonant clusters.
- **Mappings:**
  - `g` → `ng`
  - `h` → `nh`
  - `k` → `ch`
- **Challenge:** Requires syllable boundary detection. Difficult in single-pass engines.
- **Status:** Not yet implemented in uvie-rs. Requires app-layer or engine enhancement.

### 7.3 Quick Telex (`vQuickTelex`)

- **Description:** Double-press consonant keys to form clusters.
- **Mappings:**
  - `cc` → `ch`
  - `gg` → `gi`
  - `kk` → `kh`
  - `nn` → `ng`
  - `qq` → `qu`
  - `pp` → `ph`
  - `tt` → `th`
  - `uu` → `ươ`
- **Implementation:** In tone filter, detect repeated consonant keys and replace.
- **Engine impact:** Pre-processing pass before resolver.

---

## 8. Pending / Future Ideas

### 8.1 Convert Tool

- **Description:** Utility to convert selected text between code tables (Unicode ↔ TCVN3 ↔ VNI) and apply case transforms (ALL CAPS, all lower, Title Case).
- **Trigger:** Global hotkey (configurable).
- **Implementation:** Standalone text transformation function, operates on committed text (not composing).

### 8.2 Word Frequency Learning

- **Description:** Learn user's frequently typed words to improve macro suggestions or autocomplete.
- **Data model:** Trie or frequency map stored locally.
- **Privacy:** All data stays on-device.

### 8.3 Emoji / Symbol Shortcuts

- **Description:** Macro expansion for Unicode symbols.
- **Example:** `:heart:` → `❤️`, `:shrug:` → `¯\_(ツ)_/¯`

### 8.4 Clipboard Integration

- **Description:** Paste converted text directly from clipboard history.
- **Trigger:** Special hotkey sequence.

### 8.5 Multi-Monitor Support

- **Description:** Ensure system tray icon / OSD appears on the correct monitor.

### 8.6 Accessibility Enhancements

- **Description:** VoiceOver support, high-contrast UI, reduced-motion options.

---

## Architecture Reminder

```text
┌─────────────────────────────────────┐
│         App Layer (macOS)           │
│  • CGEventTap, Settings UI,         │
│  • Smart Switch, Macro Dict,        │
│  • Tray Icon, Update Checker          │
├─────────────────────────────────────┤
│         FFI Bridge (C ABI)          │
│  • uvie.h, EngineBridge.swift       │
├─────────────────────────────────────┤
│         Core Engine (Rust)          │
│  • Telex/VNI resolver,              │
│  • Tone placement,                    │
│  • Spelling validation,               │
│  • Quick consonant                  │
└─────────────────────────────────────┘
```

**Rule of thumb:** If it requires OS API (macOS/Windows/Linux), file I/O, network, or user interaction → it belongs in the **app layer**.
