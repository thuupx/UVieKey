import SwiftUI

@main
struct UVieKeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Onboarding window — only visible when the user hasn't completed
        // setup. Uses a native SwiftUI WindowGroup so macOS handles window
        // activation, focus, and lifecycle correctly (manual NSWindow from
        // an accessory-policy app fails to come to front on macOS 26).
        WindowGroup("UVieKey Setup", id: "onboarding") {
            OnboardingView()
                .background(WindowAccessor { window in
                    // Float above other apps so the user sees onboarding even
                    // if they launched UVieKey from Finder while another app
                    // was focused.
                    window.level = .floating
                })
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 560, height: 520)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultPosition(.center)

        Settings {
            SettingsView()
        }
    }
}

extension Notification.Name {
    static let onboardingCompleted = Notification.Name("UVieKeyOnboardingCompleted")
}

/// SwiftUI helper to grab the underlying NSWindow so we can set properties
/// not yet exposed by SwiftUI (e.g. `.level` on macOS 13/14).
private struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let view, let window = view.window else { return }
            callback(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var menuBar: MenuBarController?
    private let memory = MemoryManager()
    private lazy var inputMethodManager = InputMethodManager(memory: memory)
    private lazy var eventTap = EventTap(inputMethodManager: inputMethodManager)
    private let updateChecker = UpdateChecker.shared
    private let hotkeyManager = GlobalHotkeyManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
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
            // Hide dock icon — no onboarding to show.
            NSApp.setActivationPolicy(.accessory)
            // The onboarding WindowGroup auto-opens its window on every launch.
            // For returning users, close that stale window (also handled in
            // OnboardingView.onAppear, but we do it here too for robustness).
            DispatchQueue.main.async {
                for window in NSApp.windows where window.title == "UVieKey Setup" {
                    window.close()
                }
            }
            // On macOS 26 (and sometimes 15+), `AXIsProcessTrustedWithOptions`
            // returns a cached value that lags the user's actual grant. Poll
            // briefly so a user who granted permission between launches is
            // picked up without having to reopen the app (Bug #10).
            AccessibilityChecker.pollForAccess(timeout: 10) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.eventTap.start()
                    }
                    // If not granted, the onboarding WindowGroup is still
                    // open (it stays visible until the user completes it).
                }
            }
        } else {
            // Onboarding WindowGroup auto-opens on first launch because it's
            // the only window scene. Keep .regular activation policy so the
            // Dock icon appears and the window can be focused.
            NSApp.setActivationPolicy(.regular)
        }

        // Start periodic update checks (every 2h, fires once immediately).
        updateChecker.start()

        // Wire the custom global hotkey to toggle Vietnamese/English.
        hotkeyManager.onTrigger = { [weak self] in
            guard let self else { return }
            self.inputMethodManager.toggle()
            // Sync the menu bar icon immediately — the Combine pipeline
            // updates it asynchronously, which can lag on macOS 15+.
            self.menuBar?.syncFromInputMethod()
            NSSound.beep()
        }
        hotkeyManager.loadFromDefaults()
    }

    @objc private func onOnboardingCompleted() {
        // Switch back to accessory (no Dock icon) now that onboarding is done.
        NSApp.setActivationPolicy(.accessory)
        eventTap.start()
    }
}
