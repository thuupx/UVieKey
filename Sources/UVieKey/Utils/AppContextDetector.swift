import Cocoa
import ApplicationServices

/// Detects the currently focused application using AXUIElement,
/// with fallback to NSWorkspace.frontmostApplication.
/// Also detects visible Spotlight window via CGWindowList.
final class AppContextDetector {
    private var timer: Timer?
    private var _bundleID: String = ""
    private var _isSpotlightVisible: Bool = false
    private let queue = DispatchQueue(label: "uvie.appcontext")

    var bundleID: String {
        queue.sync { _bundleID }
    }

    var isSpotlightVisible: Bool {
        queue.sync { _isSpotlightVisible }
    }

    func start() {
        update()
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
                self?.update()
            }
        }
    }

    func stop() {
        DispatchQueue.main.async {
            self.timer?.invalidate()
            self.timer = nil
        }
    }

    private func update() {
        let bid = getFocusedAppBundleID() ?? getFrontmostAppBundleID()
        let spotlightVisible = isSpotlightWindowVisible()
        queue.async {
            self._bundleID = bid ?? ""
            self._isSpotlightVisible = spotlightVisible
        }
    }

    /// Primary: AXUIElement focused application.
    private func getFocusedAppBundleID() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )
        guard result == .success else { return nil }

        let app = focusedApp as! AXUIElement
        var pid: pid_t = 0
        AXUIElementGetPid(app, &pid)

        if let runningApp = NSRunningApplication(processIdentifier: pid) {
            return runningApp.bundleIdentifier
        }
        return nil
    }

    /// Fallback: NSWorkspace frontmost application.
    private func getFrontmostAppBundleID() -> String? {
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// Check if Spotlight window is visible using CGWindowList.
    private func isSpotlightWindowVisible() -> Bool {
        let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
        guard let windows = windowList else { return false }

        for window in windows {
            if let ownerName = window[kCGWindowOwnerName as String] as? String,
               ownerName == "Spotlight" {
                return true
            }
            if let windowName = window[kCGWindowName as String] as? String,
               windowName.contains("Spotlight") {
                return true
            }
        }
        return false
    }
}
