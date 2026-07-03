import Cocoa

// MARK: - App Classification

/// Default apps that need empty-character sentinel before backspace (invalidate autocomplete).
/// Matched by prefix OR exact bundle ID.
let defaultCompoundApps: Set<String> = AppDefaults.compoundApps

/// Get compound apps from UserDefaults (defaults + custom)
func getCompoundApps() -> Set<String> {
    let custom = UserDefaults.standard.stringArray(forKey: DefaultsKey.customCompoundApps) ?? []
    return defaultCompoundApps.union(Set(custom))
}

/// Apps that need Accessibility text injection instead of CGEventTap.
/// Spotlight and some secure text fields don't accept synthetic key events.
let axApps: Set<String> = AppDefaults.axApps

/// Apps that should bypass IME entirely (system UI, lock screen, etc.)
let bypassApps: Set<String> = AppDefaults.bypassApps

/// Apps the user explicitly wants to exclude from UVieKey processing.
/// Events for these apps pass through untouched.
let defaultExcludedApps: Set<String> = []

/// Get excluded apps from UserDefaults (defaults + custom)
func getExcludedApps() -> Set<String> {
    let custom = UserDefaults.standard.stringArray(forKey: DefaultsKey.customExcludedApps) ?? []
    return defaultExcludedApps.union(Set(custom))
}

/// Default Chromium browsers that need Shift+Left Arrow selection
/// instead of plain backspace (avoids duplicate chars).
let defaultChromiumBrowsers: Set<String> = AppDefaults.chromiumBrowsers

/// Get Chromium browsers from UserDefaults (defaults + custom)
func getChromiumBrowsers() -> Set<String> {
    let custom = UserDefaults.standard.stringArray(forKey: DefaultsKey.customChromiumApps) ?? []
    return defaultChromiumBrowsers.union(Set(custom))
}

func checkIsCompoundApp(_ bundleID: String) -> Bool {
    getCompoundApps().contains(bundleID)
}

func checkIsChromiumBrowser(_ bundleID: String) -> Bool {
    getChromiumBrowsers().contains(bundleID)
}

func checkIsExcludedApp(_ bundleID: String) -> Bool {
    getExcludedApps().contains(bundleID)
}

/// Returns true for shortcuts that select text (Cmd+A, Shift+arrows, etc.).
/// When the user selects text and types over it, the engine's diff state
/// becomes invalid because it cannot see the selection.
func isSelectionShortcut(keyCode: Int64, flags: CGEventFlags) -> Bool {
    let isCmdA = keyCode == 0 && flags.contains(.maskCommand)
    let isShiftArrow = flags.contains(.maskShift) && (123...126).contains(keyCode)
    return isCmdA || isShiftArrow
}
