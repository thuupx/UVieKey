import SwiftUI

// MARK: - Window Controller

@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    private override init() {}

    func show() {
        // Ensure we're on main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.show()
            }
            return
        }

        // Recreate window if it was closed or invalidated
        if window == nil || window?.isVisible == false {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.title = "UVieKey"
            w.titlebarAppearsTransparent = true
            // Default: only the title bar can move the window. Setting this to
            // true lets the user drag from anywhere inside the window background.
            w.isMovableByWindowBackground = false
            w.isReleasedWhenClosed = false
            w.delegate = self

            // Use NSHostingController for better memory management
            let controller = NSHostingController(rootView: SettingsView())
            w.contentViewController = controller

            window = w

            // Center on screen
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let windowFrame = w.frame
                let x = screenFrame.midX - windowFrame.width / 2
                let y = screenFrame.midY - windowFrame.height / 2
                w.setFrameOrigin(NSPoint(x: x, y: y))
            }
        }

        guard let w = window else { return }
        w.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Cleanup window and its content to prevent memory leaks
        if let w = notification.object as? NSWindow, w === window {
            window?.contentViewController = nil
            window?.delegate = nil
            window = nil
        }
    }
}

// MARK: - Tabs

enum SettingsTab: String, CaseIterable, Identifiable {
    case general    = "Tổng quan"
    case keyboard   = "Bàn phím"
    case macro      = "Macro"
    case apps       = "Ứng dụng"
    case advanced   = "Nâng cao"
    case about      = "Giới thiệu"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general:   return "slider.horizontal.3"
        case .keyboard:  return "keyboard"
        case .macro:     return "doc.text.magnifyingglass"
        case .apps:      return "wrench.and.screwdriver"
        case .advanced:  return "gearshape.2"
        case .about:     return "info.circle"
        }
    }
}

// MARK: - Root View  (named SettingsView to match UVieKeyApp.swift)

struct SettingsView: View {
    @State private var tab: SettingsTab = .general
    @StateObject private var updateChecker = UpdateChecker.shared

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(alignment: .leading, spacing: 2) {
                Spacer().frame(height: 20)  // below titlebar
                ForEach(SettingsTab.allCases) { t in
                    SidebarRow(
                        tab: t,
                        selected: tab == t,
                        showUpdateBadge: t == .about && updateChecker.hasUpdate,
                        onSelect: { tab = t }
                    )
                }
                Spacer()
            }
            .frame(width: 186)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Detail pane
            Group {
                switch tab {
                case .general:   GeneralPane()
                case .keyboard:  KeyboardPane()
                case .macro:     MacroPane()
                case .apps:      AppsPane()
                case .advanced:  AdvancedPane()
                case .about:     AboutPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 620, minHeight: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Sidebar Row

private struct SidebarRow: View {
    let tab: SettingsTab
    let selected: Bool
    var showUpdateBadge: Bool = false
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? .white : .secondary)
                    .frame(width: 18)
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .white : .primary)
                Spacer()
                if showUpdateBadge {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                selected ? Color.accentColor : .clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
    }
}

// MARK: - General Pane

struct GeneralPane: View {
    @AppStorage(DefaultsKey.inputMethod)    private var inputMethod: String = "telex"
    @AppStorage(DefaultsKey.smartSwitchKey) private var smartSwitchKey: Bool = false
    @AppStorage(DefaultsKey.engineEnabled)  private var engineEnabled: Bool = true
    @AppStorage(DefaultsKey.autoDisableOnNonLatinLayout) private var autoDisableOnNonLatinLayout: Bool = false
    @AppStorage(DefaultsKey.inputMethodHotkeyEnabled) private var hotkeyEnabled: Bool = true
    @AppStorage(DefaultsKey.customToggleEnabled) private var customToggleEnabled: Bool = false
    @StateObject private var launchAtLogin = LaunchAtLoginManager.shared
    @StateObject private var hotkeyManager = GlobalHotkeyManager.shared

    private var isVietnameseMode: Binding<Bool> {
        Binding(
            get: { engineEnabled },
            set: { engineEnabled = $0 }
        )
    }

    var body: some View {
        PaneScroll {
            // Engine master toggle
            SettingsCard {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(isVietnameseMode.wrappedValue ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
                            .frame(width: 44, height: 44)
                        Image(systemName: isVietnameseMode.wrappedValue ? "keyboard.fill" : "keyboard")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(isVietnameseMode.wrappedValue ? Color.accentColor : .secondary)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(isVietnameseMode.wrappedValue ? "Tiếng Việt" : "English")
                            .font(.system(size: 14, weight: .semibold))
                        Text(isVietnameseMode.wrappedValue ? "Gõ Tiếng Việt" : "English Keyboard")
                            .font(.system(size: 11))
                            .foregroundStyle(isVietnameseMode.wrappedValue ? Color.accentColor : .secondary)
                    }

                    Spacer()

                    Toggle("", isOn: isVietnameseMode)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .scaleEffect(1.1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
                .onTapGesture { isVietnameseMode.wrappedValue.toggle() }
            }
            PaneSection("Bảng mã gõ") {
                SettingsCard {
                    // Segmented picker
                    HStack(spacing: 1) {
                        imOption("Telex", "telex")
                        imOption("VNI",   "vni")
                    }
                    .padding(12)
                }
            }

            PaneSection("Thông minh") {
                SettingsCard {
                    SToggleRow("arrow.triangle.2.circlepath",
                                "Nhớ ngôn ngữ từng ứng dụng",
                                "Tự động Tiếng Việt / English khi chuyển app",
                                $smartSwitchKey)
                }
            }

            PaneSection("Phát hiện ngôn ngữ") {
                SettingsCard {
                    SToggleRow("magnifyingglass",
                                "Tự động tắt khi dùng layout khác",
                                "Bỏ qua engine khi keyboard không phải Latin layout",
                                $autoDisableOnNonLatinLayout)
                }
            }

            PaneSection("Hệ thống") {
                SettingsCard {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "power")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .center)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Khởi động cùng macOS")
                                .font(.system(size: 13, weight: .medium))
                            Text(launchAtLogin.isAvailable
                                 ? "Tự động chạy khi đăng nhập"
                                 : "Tính năng không khả dụng")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $launchAtLogin.isEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(!launchAtLogin.isAvailable)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if launchAtLogin.isAvailable {
                            launchAtLogin.isEnabled.toggle()
                        }
                    }
                }
            }

            PaneSection("Phím tắt chuyển ngôn ngữ") {
                SettingsCard {
                    // Fn toggle (existing)
                    SToggleRow("command",
                                "Phím Fn để chuyển nhanh",
                                "Nhấn phím Fn để bật / tắt Tiếng Việt",
                                $hotkeyEnabled)

                    SCardDivider()

                    // Custom global shortcut
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .center)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Phím tắt tuỳ chỉnh")
                                .font(.system(size: 13, weight: .medium))
                            Text("Phím tắt toàn hệ thống để chuyển ngôn ngữ")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $customToggleEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                    .onTapGesture { customToggleEnabled.toggle() }

                    if customToggleEnabled {
                        SCardDivider()
                        HStack(spacing: 12) {
                            Image(systemName: "record.circle")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .center)
                            Text("Lưu phím tắt")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            ShortcutRecorder()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                    }
                }
                .onChange(of: customToggleEnabled) { newValue in
                    hotkeyManager.setEnabled(newValue)
                }
            }
        }
    }

    private func imOption(_ label: String, _ tag: String) -> some View {
        let active = inputMethod == tag
        return Button { inputMethod = tag } label: {
            Text(label)
                .font(.system(size: 13, weight: active ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(active ? Color.accentColor : Color.primary.opacity(0.05),
                             in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(active ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func imRow(_ title: String, _ desc: String, tag: String) -> some View {
        let active = inputMethod == tag
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: active ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(active ? Color.accentColor : .secondary)
                .font(.system(size: 16))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(desc)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture { inputMethod = tag }
    }
}

// MARK: - Keyboard Pane

struct KeyboardPane: View {
    @AppStorage(DefaultsKey.uppercaseFirstChar) private var uppercaseFirstChar: Bool = false
    @AppStorage(DefaultsKey.relaxedCoda) private var relaxedCoda: Bool = false

    var body: some View {
        PaneScroll {
            PaneSection("Vần cuối") {
                SettingsCard {
                    SToggleRow("g.circle",
                                "Viết tắt vần cuối (g→ng, h→nh)",
                                "Bật để gõ đặg, nhàh thay vì đặng, nhành. Tiện khi gõ nhanh.",
                                $relaxedCoda)
                }
            }

            PaneSection("Tự động hóa") {
                SettingsCard {
                    SToggleRow("textformat",
                                "Viết hoa chữ cái đầu câu",
                                "Tự động viết hoa sau dấu chấm hoặc xuống dòng mới",
                                $uppercaseFirstChar)
                }
            }
        }
    }
}

// MARK: - Macro Pane

struct MacroPane: View {
    @AppStorage(DefaultsKey.macroEnabled) private var macroEnabled: Bool = false
    @StateObject private var macroManager = MacroManager.shared
    @State private var showingAddSheet = false
    @State private var newAbbreviation = ""
    @State private var newExpansion = ""

    var body: some View {
        PaneScroll {
            PaneSection("Macro văn bản") {
                SettingsCard {
                    SToggleRow("wand.and.rays",
                                "Bật Macro văn bản",
                                "Gõ viết tắt, nhấn Space / Enter để mở rộng thành văn bản đầy đủ",
                                $macroEnabled)
                }
            }

            if macroEnabled {
                PaneSection("Danh sách Macro") {
                    SettingsCard {
                        // Table header
                        HStack {
                            Text("Viết tắt")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 100, alignment: .leading)
                            Text("Văn bản thay thế")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.04))

                        ForEach(macroManager.macros) { macro in
                            SCardDivider()
                            HStack {
                                Text(macro.abbreviation)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.blue)
                                    .frame(width: 100, alignment: .leading)
                                Text(macro.expansion)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Button {
                                    macroManager.deleteMacro(macro)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                        }
                    }

                    HStack {
                        Spacer()
                        Button {
                            showingAddSheet = true
                        } label: {
                            Label("Thêm Macro", systemImage: "plus.circle.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    .sheet(isPresented: $showingAddSheet) {
                        AddMacroSheet(abbreviation: $newAbbreviation, expansion: $newExpansion) {
                            macroManager.addMacro(abbreviation: newAbbreviation, expansion: newExpansion)
                            newAbbreviation = ""
                            newExpansion = ""
                            showingAddSheet = false
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Advanced Pane

struct AdvancedPane: View {
    @AppStorage(DefaultsKey.modernOrthography) private var modernOrthography: Bool = true
    @AppStorage(DefaultsKey.quickTelex) private var quickTelex: Bool = false
    @AppStorage(DefaultsKey.quickStart) private var quickStart: Bool = false
    @AppStorage(Logger.keystrokeTraceKey) private var keystrokeTrace: Bool = false

    var body: some View {
        PaneScroll {
            PaneSection("Ngôn ngữ") {
                SettingsCard {
                    SToggleRow("book.closed",
                                "Chính tả hiện đại",
                                "Bật: hoas → hoá (quy tắc mới). Tắt: hoas → hoà (chính tả truyền thống).",
                                $modernOrthography)
                }
            }

            PaneSection("Gõ tắt Telex") {
                SettingsCard {
                    SToggleRow("bolt.fill",
                                "Quick Telex (gõ kép)",
                                "Gõ đôi phụ âm: cc→ch, gg→gi, hh→nh, kk→kh, nn→ng, qq→qu, pp→ph, tt→th.",
                                $quickTelex)
                }
                SettingsCard {
                    SToggleRow("bolt",
                                "Quick Start (gõ nhanh)",
                                "j→gi, f→ph, w→qu ở đầu từ. Tiện khi gõ nhanh.",
                                $quickStart)
                }
            }

            PaneSection("Tương thích trình duyệt") {
                SettingsCard {
                    HStack(spacing: 14) {
                        Image(systemName: "globe")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sửa lỗi Chromium / Safari")
                                .font(.system(size: 13, weight: .medium))
                            Text("Khắc phục các vấn đề khi gõ trong trình duyệt, thêm app ở tab Ứng Dụng")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.green)
                    }
                    .padding(14)
                }
            }

            PaneSection("Quyền truy cập") {
                SettingsCard {
                    Button { AccessibilityChecker.openPrivacySettings() } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Cài đặt Trợ năng (Accessibility)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text("Mở System Settings để quản lý quyền bàn phím")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                    }
                    .buttonStyle(.plain)
                }
            }

            PaneSection("Chẩn đoán") {
                SettingsCard {
                    SToggleRow("keyboard",
                                "Bật chẩn đoán",
                                "Ghi lại mỗi phím gõ để gửi báo cáo lỗi. Hãy tắt sau khi gửi log.",
                                $keystrokeTrace)
                }
                SettingsCard {
                    Button {
                        if let url = Logger.shared.writeDiagnosticsToTempFile() {
                            // Reveal the diagnostics file in Finder so the user
                            // can drag it into Mail / AirDrop / Messages.
                            // Avoids NSSharingServicePicker (which caused an
                            // over-release crash on macOS 26 — the picker is
                            // not retained and its blocks get freed during
                            // the CA transaction commit).
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "envelope")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Gửi log chẩn đoán")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text("Tạo file .txt chứa log + thông tin hệ thống, mở trong Finder để chia sẻ")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - About Pane

struct AboutPane: View {
    @StateObject private var updateChecker = UpdateChecker.shared

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 22) {
                // App icon - load from bundle if packaged, otherwise from source repo
                Image(nsImage: appIconImage())
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 92, height: 92)

                VStack(spacing: 6) {
                    Text("UVieKey")
                        .font(.system(size: 26, weight: .bold))
                    Text("Phiên bản \(AppVersion.fullVersion)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    // Changelog link
                    Link(destination: URL(string: "https://github.com/thuupx/UVieKey/releases")!) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 10))
                            Text("Xem changelog")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }

                Text("Bộ gõ Tiếng Việt nhanh, nhẹ và chính xác cho macOS.\nPowered by uvie-rs - zero-cost Rust engine.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .frame(maxWidth: 360)

                // Manual update download button
                if updateChecker.hasUpdate, let url = updateChecker.latestReleaseURL {
                    Link(destination: url) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Tải bản cập nhật v\(updateChecker.latestVersion ?? "")")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: 260)
                }
            }

            Spacer()
            Divider()

            HStack(spacing: 0) {
                aboutLink("link",                  "GitHub",     "https://github.com/thuupx/UVieKey")
                Divider().frame(height: 20)
                aboutLink("exclamationmark.bubble", "Báo lỗi",   "https://github.com/thuupx/UVieKey/issues")
                Divider().frame(height: 20)
                aboutLink("arrow.down.circle",     "Cập nhật",   "https://github.com/thuupx/UVieKey/releases")
            }
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func appIconImage() -> NSImage {
        // 1) Try the app bundle's icon (used in packaged .app builds)
        if let bundleIcon = NSImage(named: "AppIcon") {
            return bundleIcon
        }
        // 2) Fall back to the source repo path (used during `swift build` / Xcode run)
        let sourceFile = URL(fileURLWithPath: #file)
        let repoIcon = sourceFile
            .deletingLastPathComponent() // UI
            .deletingLastPathComponent() // UVieKey
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // UVieKey
            .appendingPathComponent("AppIcon.icns")
        if let repoIconImage = NSImage(contentsOf: repoIcon) {
            return repoIconImage
        }
        // 3) Last resort blank image
        return NSImage(size: NSSize(width: 92, height: 92))
    }

    private func aboutLink(_ icon: String, _ label: String, _ url: String) -> some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 14))
                Text(label).font(.system(size: 11))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared Components

struct PaneScroll<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                content
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct PaneSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .kerning(0.3)
            content
        }
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color(nsColor: .controlBackgroundColor),
                         in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }
}

struct SCardDivider: View {
    var body: some View {
        Divider().padding(.leading, 50)
    }
}

struct SToggleRow: View {
    let icon: String
    let title: String
    let description: String
    @Binding var isOn: Bool

    init(_ icon: String, _ title: String, _ description: String, _ isOn: Binding<Bool>) {
        self.icon = icon
        self.title = title
        self.description = description
        self._isOn = isOn
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}

struct ComingSoonBadge: View {
    var body: some View {
        Text("Sắp ra mắt")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.orange.opacity(0.1), in: Capsule())
    }
}

// MARK: - Add Macro Sheet

struct AddMacroSheet: View {
    @Binding var abbreviation: String
    @Binding var expansion: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Thêm Macro mới")
                .font(.system(size: 16, weight: .semibold))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Viết tắt")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Ví dụ: btw", text: $abbreviation)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Văn bản thay thế")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Ví dụ: by the way", text: $expansion)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
            }
            
            HStack(spacing: 12) {
                Button("Hủy") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Lưu") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .disabled(abbreviation.isEmpty || expansion.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
