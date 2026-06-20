import Cocoa
import Combine

extension Notification.Name {
    static let resetEngineAfterAppSwitch = Notification.Name("UVieKeyResetEngineAfterAppSwitch")
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

        // Step 2: Reset engine FIRST to clear ghost characters from previous app
        NotificationCenter.default.post(name: .resetEngineAfterAppSwitch, object: nil)

        // Step 3: THEN restore state (after engine is clean)
        if let memory, let state = memory.state(for: bundleID) {
            // Small delay to ensure engine reset completes before state restoration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
                guard let self = self else { return }
                self.isVietnamese = state.language
                self.syncEngineEnabled()
            }
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
