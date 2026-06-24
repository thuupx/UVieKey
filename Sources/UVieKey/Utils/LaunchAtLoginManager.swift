import Foundation
import ServiceManagement

/// Manages the "launch at login" toggle using SMAppService (macOS 13+).
@MainActor
final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    @Published var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled, !isInitializing, !isReverting else { return }
            apply()
        }
    }

    /// Whether the toggle is interactive in the UI. Disabled when the app is
    /// not running inside a proper .app bundle (e.g. raw `swift run`).
    @Published var isAvailable: Bool

    /// Suppresses the `didSet` during initial state sync.
    private var isInitializing = true
    /// Suppresses the `didSet` while reverting to the system state on failure.
    private var isReverting = false

    /// True when the app is running inside a proper .app bundle (required by
    /// SMAppService). Raw executables from `swift build` cannot register.
    private let isBundled: Bool = Bundle.main.bundleIdentifier != nil

    private init() {
        isAvailable = isBundled
        isEnabled = isBundled && Self.checkStatus()
        isInitializing = false
    }

    /// Reads the current registration status from SMAppService.
    private static func checkStatus() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the app based on `isEnabled`.
    private func apply() {
        // SMAppService requires a proper .app bundle. Skip silently when
        // running as a raw executable (e.g. `swift run` during development).
        guard isBundled else {
            NSLog("[UVieKey] LaunchAtLogin: skipped — app is not bundled (raw executable)")
            revert()
            return
        }

        let service = SMAppService.mainApp
        if isEnabled {
            do {
                try service.register()
            } catch {
                NSLog("[UVieKey] LaunchAtLogin: register failed — \(error.localizedDescription)")
                revert()
            }
        } else {
            // Skip unregister if already not registered — unregister() throws
            // "Invalid argument" (kSMErrorJobNotFound) in that case, but the
            // desired end state (not registered) is already achieved.
            guard service.status != .notRegistered else { return }
            do {
                try service.unregister()
            } catch {
                NSLog("[UVieKey] LaunchAtLogin: unregister failed — \(error.localizedDescription)")
                revert()
            }
        }
    }

    /// Reverts `isEnabled` to the actual system state without re-triggering `apply`.
    private func revert() {
        isReverting = true
        isEnabled = isBundled && Self.checkStatus()
        isReverting = false
    }

    /// Re-syncs from the system status (call after app launch or window open).
    func refresh() {
        isReverting = true
        isEnabled = isBundled && Self.checkStatus()
        isReverting = false
    }
}
