import SwiftUI
import Combine

// MARK: - Controller

@MainActor
final class MenuBarController: ObservableObject {
    @Published var isVietnamese = true

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventTap: EventTap?
    private var inputMethodManager: InputMethodManager?
    private var cancellables = Set<AnyCancellable>()
    private var defaultsObserver: NSObjectProtocol?

    var keepPopoverOpen: Bool {
        get { UserDefaults.standard.bool(forKey: DefaultsKey.keepPopoverOpen) }
        set {
            UserDefaults.standard.set(newValue, forKey: DefaultsKey.keepPopoverOpen)
            updatePopoverBehavior()
        }
    }

    var inputMethod: InputMethod {
        get { inputMethodManager?.inputMethod ?? .telex }
        set {
            inputMethodManager?.inputMethod = newValue
            // Route through applyEngineSettings so the shared engine
            // (used by both EventTap and AXTextInjector) is updated.
            eventTap?.applyEngineSettings()
        }
    }

    init() {
        setupStatusItem()
        setupPopover()
    }

    func setEventTap(_ tap: EventTap) {
        self.eventTap = tap
        self.inputMethodManager = tap.inputMethodManager
        tap.inputMethodManager.$isVietnamese
            .receive(on: DispatchQueue.main)
            .sink { [weak self] val in
                self?.isVietnamese = val
                self?.updateIcon()
            }
            .store(in: &cancellables)
    }

    // MARK: Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.action = #selector(togglePopover)
            button.target = self
        }
        updateIcon()
    }

    private func setupPopover() {
        let p = NSPopover()
        p.contentSize = NSSize(width: 280, height: 388)
        p.behavior = keepPopoverOpen ? .applicationDefined : .transient
        p.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(controller: self)
        )
        popover = p

        // Observe defaults changes
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updatePopoverBehavior()
            }
        }
    }

    private func updatePopoverBehavior() {
        popover?.behavior = keepPopoverOpen ? .applicationDefined : .transient
    }

    deinit {
        if let observer = defaultsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        cancellables.removeAll()
    }

    // MARK: Icon - drawn as NSImage for pixel-perfect vertical centering

    private func updateIcon() {
        let button = statusItem?.button
        // Force the status item to discard the cached image representation.
        // On macOS 15+, assigning a new NSImage with the same dimensions to
        // the button doesn't always trigger a redraw — clearing first ensures
        // the new image is picked up.
        button?.image = nil
        button?.image = makeIcon()
        button?.title = ""
    }

    private func makeIcon() -> NSImage {
        let label = isVietnamese ? "V" : "E"
        let color = isVietnamese ? NSColor(red: 0.808, green: 0.255, blue: 0.169, alpha: 1.0) : NSColor.secondaryLabelColor
        let sz = NSSize(width: 20, height: 18)
        // Pre-render into a bitmap instead of using a lazy drawing handler.
        // The drawing-handler variant (NSImage(size:flipped:drawingHandler:))
        // can be cached by the status item on macOS 15 and fail to re-render
        // when a new image instance is assigned.
        let img = NSImage(size: sz)
        img.lockFocus()
        let font = NSFont.systemFont(ofSize: 18, weight: .bold)
        let str = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: color])
        let s = str.size()
        str.draw(at: NSPoint(x: (sz.width - s.width) / 2,
                             y: (sz.height - s.height) / 2))
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    // MARK: Actions

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if let popover, popover.isShown {
            popover.close()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func toggle() {
        inputMethodManager?.toggle()
        // Read the value directly from the source of truth instead of our
        // cached @Published copy, which is updated asynchronously by the
        // Combine sink and would still hold the OLD value at this point.
        if let imm = inputMethodManager {
            isVietnamese = imm.isVietnamese
        }
        updateIcon()
    }

    /// Sync the local `isVietnamese` state and icon from the input method
    /// manager. Used by callers (global hotkey, app switch) that toggle the
    /// engine outside of `MenuBarController.toggle()` and need the icon to
    /// update immediately rather than waiting for the async Combine sink.
    func syncFromInputMethod() {
        if let imm = inputMethodManager {
            isVietnamese = imm.isVietnamese
        }
        updateIcon()
    }

    func openSettings() {
        // Close popover safely
        if let popover, popover.isShown {
            popover.close()
        }

        SettingsWindow.shared.show()
    }

    func quit() { NSApp.terminate(nil) }

    // Keep @objc selectors for backwards compatibility
    @objc private func toggleInputMethod() { toggle() }
    @objc private func openSettingsMenu()  { openSettings() }
    @objc private func quitApp()           { quit() }
}
