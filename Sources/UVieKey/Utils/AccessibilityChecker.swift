import Cocoa
import IOKit.hid

/// Checks and requests Accessibility (and Input Monitoring on macOS 15+)
/// permission for CGEventTap.
///
/// On macOS 15 (Sequoia) and later, `CGEvent.tapCreate` requires BOTH
/// Accessibility AND Input Monitoring permission. On macOS 26 (Tahoe),
/// `AXIsProcessTrustedWithOptions` can return a cached `false` for several
/// seconds after the user toggles the switch in System Settings, so callers
/// must poll rather than rely on a one-shot read.
enum AccessibilityChecker {
    static var isTrusted: Bool {
        AXIsProcessTrustedWithOptions(nil)
    }

    /// True on macOS 15 (Sequoia) or later, where Input Monitoring is also
    /// required for `CGEvent.tapCreate`.
    static var requiresInputMonitoring: Bool {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.majorVersion >= 15
    }

    /// On macOS 15+, query Input Monitoring permission via IOKit.
    /// Returns `true` on older OSes (permission not required).
    /// Wrapped in a try? — `IOHIDCheckAccess` can throw an ObjC exception
    /// when the process has no valid bundle identity (e.g. `swift run`
    /// without a signed .app), which would crash the app.
    static var isInputMonitoringTrusted: Bool {
        guard requiresInputMonitoring else { return true }
        return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// True only when BOTH permissions are granted (or Input Monitoring is
    /// not required on this OS).
    static var isFullyTrusted: Bool {
        isTrusted && isInputMonitoringTrusted
    }

    /// Request Accessibility permission (shows the system prompt).
    /// Does NOT call `IOHIDRequestAccess` — on macOS 26 that API can
    /// destabilize the process when invoked from an unsigned `swift run`
    /// binary. The user grants Input Monitoring via System Settings
    /// (the onboarding provides a button to open the right pane).
    static func requestAccess() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: NSDictionary = [prompt: true]
        AXIsProcessTrustedWithOptions(options)
    }

    static func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Open the Input Monitoring pane (macOS 15+).
    static func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_InputMonitoring") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Poll both permissions until both are granted or `timeout` elapses.
    /// Use this instead of one-shot `isTrusted` checks (Bug #10: the cached
    /// value can lag the user's toggle on macOS 26).
    static func pollForAccess(timeout: TimeInterval = 60, callback: @escaping (Bool) -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        func check() {
            if isFullyTrusted {
                callback(true)
                return
            }
            if Date() < deadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: check)
            } else {
                callback(false)
            }
        }
        check()
    }
}
