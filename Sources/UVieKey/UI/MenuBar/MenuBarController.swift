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
        p.behavior = .transient
        p.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(controller: self)
        )
        popover = p
    }

    deinit {
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
        // Rounded-rect outline with "V" (Vietnamese, red) or "E" (English, gray).
        // isTemplate = false so the letter colors render as-is.
        let sz = NSSize(width: 24, height: 20)
        let img = NSImage(size: sz)
        img.lockFocus()

        let inset: CGFloat = 2.0
        let corner: CGFloat = 4.0
        let rect = NSRect(x: inset,
                          y: inset,
                          width: sz.width - inset * 2,
                          height: sz.height - inset * 2)
        let letter = isVietnamese ? "V" : "E"
        let color: NSColor = isVietnamese ? .systemRed : .systemGray
        let path = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
        path.lineWidth = 1.2
        color.setStroke()
        path.stroke()

        // Draw the letter centered inside the rounded rect.
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 12),
            .foregroundColor: color
        ]
        let str = NSString(string: letter)
        let size = str.size(withAttributes: attrs)
        let letterRect = NSRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        str.draw(in: letterRect, withAttributes: attrs)

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
