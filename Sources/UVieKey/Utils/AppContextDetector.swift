import Cocoa
import ApplicationServices
import Combine

/// Detects the currently focused application using AXUIElement,
/// with fallback to NSWorkspace.frontmostApplication.
///
/// Uses NSWorkspace.didActivateApplicationNotification instead of polling.
/// Spotlight detection was removed — it's handled via `AppDefaults.axApps`
/// which contains "com.apple.Spotlight", so AX mode kicks in automatically
/// when Spotlight is the frontmost app.
final class AppContextDetector {
    private var _bundleID: String = ""
    private var cancellables = Set<AnyCancellable>()

    var bundleID: String {
        // Read from CGEventTap callback (main runloop) and from
        // NSWorkspace notification handler (main). No queue needed.
        _bundleID
    }

    func start() {
        // Initial value
        update()

        // Listen for app activations instead of polling.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication else { return }
                self?.update(for: app)
            }
            .store(in: &cancellables)
    }

    /// Update bundleID directly from an NSRunningApplication. Used by
    /// EventTap to ensure bundleID is current before checking excluded state
    /// (Bug #12: Combine sink order between AppContextDetector and
    /// InputMethodManager is not guaranteed, so appDetector.bundleID could
    /// be stale when resetEngineAfterAppSwitch fires).
    func updateBundleID(_ app: NSRunningApplication) {
        _bundleID = app.bundleIdentifier ?? ""
    }

    func stop() {
        cancellables.removeAll()
    }

    /// Update on app switch notification. Uses the NSRunningApplication
    /// from the notification when available (avoids an extra AX call),
    /// falling back to AXUIElement focused-app lookup.
    private func update(for app: NSRunningApplication) {
        // The notification's app is the newly activated app — use its
        // bundleIdentifier directly. This is cheaper than AXUIElement.
        _bundleID = app.bundleIdentifier ?? ""
    }

    /// Initial update — no notification payload, so do the full lookup.
    private func update() {
        _bundleID = getFocusedAppBundleID() ?? getFrontmostAppBundleID() ?? ""
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
}
