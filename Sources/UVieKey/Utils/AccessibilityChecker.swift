import Cocoa
import IOKit

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
    static var isInputMonitoringTrusted: Bool {
        guard requiresInputMonitoring else { return true }
        // kIOHIDRequestTypeListenEvent == 0 on macOS 14+; the symbol is
        // available since 10.15 but only enforced on 15+.
        return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// True only when BOTH permissions are granted (or Input Monitoring is
    /// not required on this OS).
    static var isFullyTrusted: Bool {
        isTrusted && isInputMonitoringTrusted
    }

    static func requestAccess() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: NSDictionary = [prompt: true]
        AXIsProcessTrustedWithOptions(options)
        // On macOS 15+, also request Input Monitoring. The API returns the
        // current state and triggers the system prompt if not yet decided.
        if requiresInputMonitoring {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
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
