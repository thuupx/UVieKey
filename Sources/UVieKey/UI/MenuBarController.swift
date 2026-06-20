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
    }

    // MARK: Icon - drawn as NSImage for pixel-perfect vertical centering

    private func updateIcon() {
        statusItem?.button?.image = makeIcon()
        statusItem?.button?.title = ""
    }

    private func makeIcon() -> NSImage {
        let label = isVietnamese ? "V" : "E"
        let color = isVietnamese ? NSColor.controlAccentColor : NSColor.secondaryLabelColor
        let sz = NSSize(width: 20, height: 18)
        let img = NSImage(size: sz, flipped: false) { rect in
            let font = NSFont.systemFont(ofSize: 18, weight: .bold)
            let str = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: color])
            let s = str.size()
            str.draw(at: NSPoint(x: (rect.width - s.width) / 2,
                                 y: (rect.height - s.height) / 2))
            return true
        }
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

// MARK: - Popover View

struct MenuBarPopoverView: View {
    @ObservedObject var controller: MenuBarController
    @StateObject private var clipboardManager = ClipboardManager.shared
    @AppStorage(DefaultsKey.inputMethod)        private var inputMethod: String = "telex"
    @AppStorage(DefaultsKey.smartSwitchKey)     private var smartSwitchKey: Bool = false
    @AppStorage(DefaultsKey.uppercaseFirstChar) private var uppercaseFirstChar: Bool = false
    @AppStorage(DefaultsKey.macroEnabled)       private var macroEnabled: Bool = false
    @AppStorage(DefaultsKey.autoDisableOnNonLatinLayout) private var autoDisableOnNonLatinLayout: Bool = false
    @AppStorage(DefaultsKey.keepPopoverOpen)    private var keepPopoverOpen: Bool = false
    @StateObject private var layoutMonitor = KeyboardLayoutMonitor.shared

    var body: some View {
        VStack(spacing: 0) {
            popoverHeader
            Divider()
            languageToggle
            Divider().padding(.horizontal, 12)
            inputMethodRow
            Divider().padding(.horizontal, 12)
            featureRows
            Divider()
            clipboardSection
            Divider()
            popoverFooter
        }
        .frame(width: 280)
    }

    // MARK: Header

    private var popoverHeader: some View {
        HStack(spacing: 8) {
            Text("UVieKey")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text(AppVersion.fullVersion)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.primary.opacity(0.07), in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: Engine Toggle

    private var isVietnameseMode: Binding<Bool> {
        Binding(
            get: { controller.isVietnamese },
            set: { newValue in
                if controller.isVietnamese != newValue {
                    controller.toggle()
                }
            }
        )
    }

    private var engineToggle: some View {
        HStack(spacing: 10) {
            Image(systemName: isVietnameseMode.wrappedValue ? "keyboard.fill" : "keyboard")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isVietnameseMode.wrappedValue ? Color.accentColor : .secondary)
                .frame(width: 16)
            Text(isVietnameseMode.wrappedValue ? "Tiếng Việt" : "English")
                .font(.system(size: 12))
            Spacer()
            Toggle("", isOn: isVietnameseMode)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { isVietnameseMode.wrappedValue.toggle() }
    }

    // MARK: Language Toggle

    private var languageToggle: some View {
        HStack(spacing: 8) {
            PopoverLangButton(label: "Tiếng Việt", flag: "VI", active: controller.isVietnamese) {
                if !controller.isVietnamese { controller.toggle() }
            }
            PopoverLangButton(label: "English", flag: "EN", active: !controller.isVietnamese) {
                if controller.isVietnamese { controller.toggle() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: Input Method

    private var inputMethodRow: some View {
        HStack {
            Text("Bảng mã")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 1) {
                imPill("Telex", "telex")
                imPill("VNI",   "vni")
            }
            .padding(2)
            .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func imPill(_ label: String, _ tag: String) -> some View {
        let active = inputMethod == tag
        return Button { inputMethod = tag } label: {
            Text(label)
                .font(.system(size: 11, weight: active ? .semibold : .regular))
                .frame(width: 50, height: 22)
                .background(active ? Color.accentColor : .clear,
                             in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(active ? .white : .primary)
        }
        .buttonStyle(.plain)
        .disabled(!controller.isVietnamese)
    }

    // MARK: Feature Rows

    private var featureRows: some View {
        VStack(spacing: 0) {
            rowLabel("TÍNH NĂNG")
            toggleRow("brain","Nhớ ngôn ngữ từng app",      $smartSwitchKey)
            toggleRow("textformat",                  "Viết hoa đầu câu",           $uppercaseFirstChar)
            rowLabel("GÕ NHANH")
            toggleRow("doc.text",                    "Macro văn bản",              $macroEnabled)

            rowLabel("MENUBAR")
            toggleRow("pin",                           "Giữ mở",                    $keepPopoverOpen)

            // Show when non-Latin layout detected
            if autoDisableOnNonLatinLayout && layoutMonitor.isNonLatinLayout {
                rowLabel("PHÁT HIỆN LAYOUT")
                HStack(spacing: 10) {
                    Image(systemName: "globe")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.orange)
                        .frame(width: 16)
                    Text("Non-Latin layout - Engine tạm tắt")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }

    private func rowLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.tertiary)
                .kerning(0.4)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 9)
        .padding(.bottom, 2)
    }

    private func toggleRow(_ icon: String, _ label: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 12))
            Spacer()
            Toggle("", isOn: binding)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture { binding.wrappedValue.toggle() }
    }

    // MARK: Clipboard

    @ViewBuilder
    private var clipboardSection: some View {
        if !clipboardManager.history.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    rowLabel("CLIPBOARD")
                    Spacer()
                    Button {
                        clipboardManager.clearHistory()
                    } label: {
                        Text("Xoá tất cả")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 12)
                }
                ForEach(Array(clipboardManager.previewItems.enumerated()), id: \.offset) { _, item in
                    clipboardRow(item: item)
                }
            }
        }
    }

    private func clipboardRow(item: String) -> some View {
        let isCopied = clipboardManager.recentlyCopiedString == item
        return Button {
            clipboardManager.copyToClipboard(item)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(truncate(item, limit: 30))
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer()
                if isCopied {
                    HStack(spacing: 3) {
                        Text("Đã sao chép")
                            .font(.system(size: 10, weight: .medium))
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private func truncate(_ text: String, limit: Int) -> String {
        if text.count <= limit { return text }
        return String(text.prefix(limit)) + "…"
    }

    // MARK: Footer

    private var popoverFooter: some View {
        HStack(spacing: 0) {
            footerBtn("gearshape", "Cài đặt") { controller.openSettings() }
            Divider().frame(height: 18)
            footerBtn("power", "Thoát")        { controller.quit() }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func footerBtn(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11))
                Text(label).font(.system(size: 12))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Language Button

private struct PopoverLangButton: View {
    let label: String
    let flag: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(flag).font(.system(size: 13, weight: .bold))
                Text(label)
                    .font(.system(size: 12, weight: active ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(active ? Color.accentColor : .primary.opacity(0.06),
                         in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(active ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
