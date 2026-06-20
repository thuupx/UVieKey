import Cocoa

/// Checks and requests Accessibility permission for CGEventTap.
enum AccessibilityChecker {
    static var isTrusted: Bool {
        AXIsProcessTrustedWithOptions(nil)
    }

    static func requestAccess() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: NSDictionary = [prompt: true]
        AXIsProcessTrustedWithOptions(options)
    }

    static func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    static func pollForAccess(timeout: TimeInterval = 60, callback: @escaping (Bool) -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        func check() {
            if isTrusted {
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
