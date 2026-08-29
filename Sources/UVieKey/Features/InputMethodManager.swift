import Cocoa
import Combine

extension Notification.Name {
    static let resetEngineAfterAppSwitch = Notification.Name("UVieKeyResetEngineAfterAppSwitch")
    /// Posted when the `CGEventTap` is successfully created (after retries).
    static let eventTapDidStart = Notification.Name("UVieKeyEventTapDidStart")
    /// Posted when the `CGEventTap` cannot be created after all retries.
    /// The host should prompt the user to restart the app.
    static let eventTapStartFailed = Notification.Name("UVieKeyEventTapStartFailed")
}

/// Manages Vietnamese/English toggle, hotkeys, and per-app state.
final class InputMethodManager: ObservableObject {
    @Published var isVietnamese = true
    @Published var currentAppBundleID = ""

    private var memory: MemoryManager?
    private var cancellables = Set<AnyCancellable>()
    private var isSyncingFromDefaults = false

    var inputMethod: InputMethod {
        get {
            let raw = UserDefaults.standard.string(forKey: DefaultsKey.inputMethod) ?? "telex"
            return raw == "vni" ? .vni : .telex
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: DefaultsKey.inputMethod)
        }
    }

    init(memory: MemoryManager? = nil) {
        self.memory = memory
        isVietnamese = UserDefaults.standard.bool(forKey: DefaultsKey.engineEnabled)
        setupAppSwitchObserver()
        observeEngineEnabledChanges()
    }

    deinit {
        cancellables.removeAll()
    }

    func toggle() {
        isVietnamese.toggle()
        syncEngineEnabled()
        saveCurrentAppState()
    }

    func setVietnamese(_ value: Bool) {
        guard isVietnamese != value else { return }
        isVietnamese = value
        syncEngineEnabled()
        saveCurrentAppState()
    }

    // MARK: - App Switch

    private func setupAppSwitchObserver() {
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.handleAppSwitch(to: app.bundleIdentifier ?? "")
            }
            .store(in: &cancellables)
    }

    private func handleAppSwitch(to bundleID: String) {
        guard !bundleID.isEmpty else { return }

        // Step 1: Save state for previous app
        saveCurrentAppState()

        currentAppBundleID = bundleID

        // Step 2: Reset engine FIRST to clear ghost characters from previous app.
        // NotificationCenter.default.post is synchronous — the engine reset
        // completes before this method continues, so there is no need for a
        // delay before restoring state. The previous 10ms asyncAfter created a
        // race window where a fast keystroke could use the wrong language.
        NotificationCenter.default.post(name: .resetEngineAfterAppSwitch, object: nil)

        // Step 3: Restore state immediately (engine is already clean).
        if let memory, let state = memory.state(for: bundleID) {
            isVietnamese = state.language
            syncEngineEnabled()
        }
    }

    private func saveCurrentAppState() {
        guard !currentAppBundleID.isEmpty else { return }
        memory?.setState(language: isVietnamese, for: currentAppBundleID)
    }

    private func syncEngineEnabled() {
        guard !isSyncingFromDefaults else { return }
        UserDefaults.standard.set(isVietnamese, forKey: DefaultsKey.engineEnabled)
    }

    private func observeEngineEnabledChanges() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let enabled = UserDefaults.standard.bool(forKey: DefaultsKey.engineEnabled)
                guard self.isVietnamese != enabled else { return }
                self.isSyncingFromDefaults = true
                self.isVietnamese = enabled
                self.isSyncingFromDefaults = false
            }
            .store(in: &cancellables)
    }
}
