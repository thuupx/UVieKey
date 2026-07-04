import Foundation
import AppKit
import Sparkle

/// Singleton wrapper around Sparkle's SPUStandardUpdaterController.
///
/// The controller is created once in AppDelegate and shared here so the
/// About pane can trigger manual update checks (`checkForUpdates()`) and
/// query the updater state without holding a direct reference to the
/// AppDelegate. In dev builds (no .app bundle), the controller is nil and
/// `checkForUpdates()` falls back to opening the GitHub releases page.
@MainActor
final class UpdateManager {
    static let shared = UpdateManager()

    private(set) var controller: SPUStandardUpdaterController?

    private init() {}

    /// Called by AppDelegate after creating the controller.
    func register(_ controller: SPUStandardUpdaterController) {
        self.controller = controller
    }

    /// Trigger Sparkle's standard "Check for Updates…" UI.
    /// Falls back to opening GitHub releases page in browser when Sparkle
    /// is not available (dev builds without a .app bundle).
    func checkForUpdates() {
        if let controller {
            controller.checkForUpdates(nil)
        } else if let url = URL(string: "https://github.com/thuupx/UVieKey/releases") {
            NSWorkspace.shared.open(url)
        }
    }

    /// True when Sparkle can check for updates (network available, etc.).
    var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }

    /// True when Sparkle is available (running from a .app bundle).
    var isAvailable: Bool {
        controller != nil
    }
}
