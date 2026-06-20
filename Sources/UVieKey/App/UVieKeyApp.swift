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
    private let menuBar = MenuBarController()
    private let memory = MemoryManager()
    private lazy var inputMethodManager = InputMethodManager(memory: memory)
    private lazy var eventTap = EventTap(inputMethodManager: inputMethodManager)
    private weak var onboardingWindow: NSWindow?

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
            DefaultsKey.inputMethod:        "telex",
            DefaultsKey.clipboardHistoryEnabled: true,
            DefaultsKey.clipboardMaxEntries: 10,
            DefaultsKey.clipboardAutoSplitEnabled: false,
            DefaultsKey.clipboardSplitDelimiter: "newline",
            DefaultsKey.clipboardSplitMinLength: 3,
            DefaultsKey.inputMethodHotkeyEnabled: true,
            DefaultsKey.autoDisableOnNonLatinLayout: true,
            DefaultsKey.keepPopoverOpen: false,
        ])

        ClipboardManager.shared.startObserving()

        menuBar.setEventTap(eventTap)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onOnboardingCompleted),
            name: .onboardingCompleted,
            object: nil
        )

        let onboardingDone = UserDefaults.standard.bool(forKey: DefaultsKey.onboardingCompleted)
        if onboardingDone && AccessibilityChecker.isTrusted {
            eventTap.start()
        } else {
            showOnboarding()
        }
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
