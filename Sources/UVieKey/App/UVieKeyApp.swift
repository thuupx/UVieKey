import SwiftUI

@main
struct UVieKeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

extension Notification.Name {
    static let onboardingCompleted = Notification.Name("UVieKeyOnboardingCompleted")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var menuBar: MenuBarController?
    private let memory = MemoryManager()
    private lazy var inputMethodManager = InputMethodManager(memory: memory)
    private lazy var eventTap = EventTap(inputMethodManager: inputMethodManager)
    private weak var onboardingWindow: NSWindow?
    private let updateChecker = UpdateChecker.shared
    private let hotkeyManager = GlobalHotkeyManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // Hide dock icon

        // Register factory defaults - only applied if key has never been set
        UserDefaults.standard.register(defaults: [
            DefaultsKey.engineEnabled:      true,
            DefaultsKey.checkSpelling:      true,
            DefaultsKey.smartSwitchKey:     true,
            DefaultsKey.uppercaseFirstChar: false,
            DefaultsKey.macroEnabled:       false,
            DefaultsKey.modernOrthography:  true,
            DefaultsKey.relaxedCoda:        false,
            DefaultsKey.inputMethod:        "telex",
            DefaultsKey.inputMethodHotkeyEnabled: true,
            DefaultsKey.autoDisableOnNonLatinLayout: true,
            DefaultsKey.keepPopoverOpen: false,
            DefaultsKey.quickTelex:         false,
            DefaultsKey.quickStart:         false,
        ])

        menuBar = MenuBarController()
        menuBar?.setEventTap(eventTap)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onOnboardingCompleted),
            name: .onboardingCompleted,
            object: nil
        )

        let onboardingDone = UserDefaults.standard.bool(forKey: DefaultsKey.onboardingCompleted)
        if onboardingDone {
            // On macOS 26 (and sometimes 15+), `AXIsProcessTrustedWithOptions`
            // returns a cached value that lags the user's actual grant. Poll
            // briefly so a user who granted permission between launches is
            // picked up without having to reopen the app (Bug #10).
            AccessibilityChecker.pollForAccess(timeout: 10) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.eventTap.start()
                    } else {
                        // Trust not yet active — show onboarding again so the
                        // user can re-grant. The onboarding's poll will start
                        // the tap once trust comes through.
                        self.showOnboarding()
                    }
                }
            }
        } else {
            showOnboarding()
        }

        // Start periodic update checks (every 2h, fires once immediately).
        updateChecker.start()

        // Wire the custom global hotkey to toggle Vietnamese/English.
        hotkeyManager.onTrigger = { [weak self] in
            self?.inputMethodManager.toggle()
            NSSound.beep()
        }
        hotkeyManager.loadFromDefaults()
    }

    @objc private func onOnboardingCompleted() {
        onboardingWindow?.close()
        onboardingWindow = nil
        eventTap.start()
    }

    private func showOnboarding() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "UVieKey"
        window.contentView = NSHostingView(rootView: OnboardingView())
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }
}
