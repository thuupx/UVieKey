import SwiftUI
import AppKit

// MARK: - Icon Cache

@MainActor
final class AppIconCache {
    static let shared = AppIconCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 200
    }

    func icon(for bundleID: String) -> NSImage? {
        let key = bundleID as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let image = loadIcon(for: bundleID)
        if let image = image {
            cache.setObject(image, forKey: key)
        }
        return image
    }

    private func loadIcon(for bundleID: String) -> NSImage? {
        // Try to get icon from running app first
        if let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            return resize(runningApp.icon)
        }

        // If not running, try to get icon from app path
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return resize(NSWorkspace.shared.icon(forFile: appURL.path))
        }

        return nil
    }

    private func resize(_ image: NSImage?) -> NSImage? {
        guard let image = image else { return nil }
        let targetSize = NSSize(width: 64, height: 64)
        guard image.size.width > targetSize.width || image.size.height > targetSize.height else {
            return image
        }

        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: targetSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        resized.unlockFocus()
        return resized
    }
}

// MARK: - Apps Pane

struct AppsPane: View {
    @State private var compoundApps: [AppEntry] = []
    @State private var chromiumApps: [AppEntry] = []
    @State private var showingAppPicker = false
    @State private var pickerMode: PickerMode = .compound
    @State private var availableApps: [RunningApp] = []

    private let defaultCompoundApps: [String] = [
        "com.apple.Safari",
        "com.apple.Notes",
        "com.apple.TextEdit",
        "com.apple.mail",
        "com.apple.iWork",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.brave.Browser",
        "com.brave.Browser.nightly",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Dev",
        "com.microsoft.edgemac.Beta",
        "com.microsoft.Edge.Dev",
        "com.microsoft.Edge",
        "org.chromium.Chromium",
    ]

    private let defaultChromiumApps: [String] = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.brave.Browser",
        "com.brave.Browser.nightly",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Dev",
        "com.microsoft.edgemac.Beta",
        "com.microsoft.Edge.Dev",
        "com.microsoft.Edge",
        "org.chromium.Chromium",
        "ai.perplexity.comet",
    ]

    enum PickerMode {
        case compound
        case chromium
    }

    struct AppEntry: Identifiable {
        let id = UUID()
        let bundleID: String
        let icon: NSImage?
    }

    var body: some View {
        PaneScroll {
            PaneSection("Compound Apps") {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Các ứng dụng cần xử lý đặc biệt")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Text("Các app này cần gửi ký tự rỗng trước khi backspace để tránh lỗi autocomplete.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)

                        Divider()

                        if compoundApps.isEmpty {
                            Text("Chưa có ứng dụng nào")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 20)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(compoundApps.enumerated()), id: \.element.id) { idx, entry in
                                    AppRow(bundleID: entry.bundleID, icon: entry.icon) {
                                        removeCompoundApp(at: idx)
                                    }
                                    if idx < compoundApps.count - 1 {
                                        Divider()
                                    }
                                }
                            }
                        }

                        Divider()

                        HStack {
                            Button {
                                pickerMode = .compound
                                showingAppPicker = true
                            } label: {
                                Label("Thêm ứng dụng", systemImage: "plus")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)

                            Spacer()

                            Button {
                                resetCompoundToDefaults()
                            } label: {
                                Text("Reset mặc định")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }

            PaneSection("Chromium Browsers") {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Các trình duyệt Chromium cần workaround")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Text("Các app này dùng Shift+Left Arrow thay vì backspace để tránh duplicate characters.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)

                        Divider()

                        if chromiumApps.isEmpty {
                            Text("Chưa có ứng dụng nào")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 20)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(chromiumApps.enumerated()), id: \.element.id) { idx, entry in
                                    AppRow(bundleID: entry.bundleID, icon: entry.icon) {
                                        removeChromiumApp(at: idx)
                                    }
                                    if idx < chromiumApps.count - 1 {
                                        Divider()
                                    }
                                }
                            }
                        }

                        Divider()

                        HStack {
                            Button {
                                pickerMode = .chromium
                                showingAppPicker = true
                            } label: {
                                Label("Thêm ứng dụng", systemImage: "plus")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)

                            Spacer()

                            Button {
                                resetChromiumToDefaults()
                            } label: {
                                Text("Reset mặc định")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
        }
        .sheet(isPresented: $showingAppPicker) {
            AppPickerSheet(availableApps: availableApps) { selectedBundleID in
                switch pickerMode {
                case .compound:
                    addCompoundApp(selectedBundleID)
                case .chromium:
                    addChromiumApp(selectedBundleID)
                }
            }
        }
        .onChange(of: showingAppPicker) { isShowing in
            if isShowing {
                loadAvailableApps()
            }
        }
        .onAppear {
            loadCompoundApps()
            loadChromiumApps()
        }
    }

    // MARK: - Helper Methods

    private func loadCompoundApps() {
        let custom = UserDefaults.standard.stringArray(forKey: DefaultsKey.customCompoundApps) ?? []
        let allBundleIDs = defaultCompoundApps + custom
        compoundApps = allBundleIDs.map { bundleID in
            AppEntry(bundleID: bundleID, icon: AppIconCache.shared.icon(for: bundleID))
        }
    }

    private func saveCompoundApps() {
        let custom = compoundApps.map { $0.bundleID }.filter { !defaultCompoundApps.contains($0) }
        UserDefaults.standard.set(custom, forKey: DefaultsKey.customCompoundApps)
    }

    private func addCompoundApp(_ bundleID: String) {
        compoundApps.append(AppEntry(bundleID: bundleID, icon: AppIconCache.shared.icon(for: bundleID)))
        saveCompoundApps()
    }

    private func removeCompoundApp(at index: Int) {
        guard index < compoundApps.count else { return }
        compoundApps.remove(at: index)
        saveCompoundApps()
    }

    private func resetCompoundToDefaults() {
        compoundApps = defaultCompoundApps.map { bundleID in
            AppEntry(bundleID: bundleID, icon: AppIconCache.shared.icon(for: bundleID))
        }
        saveCompoundApps()
    }

    private func loadChromiumApps() {
        let custom = UserDefaults.standard.stringArray(forKey: DefaultsKey.customChromiumApps) ?? []
        let allBundleIDs = defaultChromiumApps + custom
        chromiumApps = allBundleIDs.map { bundleID in
            AppEntry(bundleID: bundleID, icon: AppIconCache.shared.icon(for: bundleID))
        }
    }

    private func saveChromiumApps() {
        let custom = chromiumApps.map { $0.bundleID }.filter { !defaultChromiumApps.contains($0) }
        UserDefaults.standard.set(custom, forKey: DefaultsKey.customChromiumApps)
    }

    private func addChromiumApp(_ bundleID: String) {
        chromiumApps.append(AppEntry(bundleID: bundleID, icon: AppIconCache.shared.icon(for: bundleID)))
        saveChromiumApps()
    }

    private func removeChromiumApp(at index: Int) {
        guard index < chromiumApps.count else { return }
        chromiumApps.remove(at: index)
        saveChromiumApps()
    }

    private func resetChromiumToDefaults() {
        chromiumApps = defaultChromiumApps.map { bundleID in
            AppEntry(bundleID: bundleID, icon: AppIconCache.shared.icon(for: bundleID))
        }
        saveChromiumApps()
    }

    private func loadAvailableApps() {
        let runningApps = NSWorkspace.shared.runningApplications
        let currentList: [AppEntry]
        switch pickerMode {
        case .compound:
            currentList = compoundApps
        case .chromium:
            currentList = chromiumApps
        }

        let currentBundleIDs = Set(currentList.map { $0.bundleID })

        availableApps = runningApps
            .filter { $0.bundleIdentifier != nil && $0.activationPolicy == .regular }
            .filter { !currentBundleIDs.contains($0.bundleIdentifier!) }
            .map { app in
                let icon = AppIconCache.shared.icon(for: app.bundleIdentifier!) ?? app.icon
                return RunningApp(bundleID: app.bundleIdentifier!, name: app.localizedName ?? "Unknown", icon: icon)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func appName(from bundleID: String) -> String {
        let parts = bundleID.split(separator: ".")
        if let last = parts.last {
            return String(last)
        }
        return bundleID
    }
}

// MARK: - App Row

private struct AppRow: View {
    let bundleID: String
    let icon: NSImage?
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 24, height: 24)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(appName(from: bundleID))
                    .font(.system(size: 13, weight: .medium))
                Text(bundleID)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                onRemove()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func appName(from bundleID: String) -> String {
        let parts = bundleID.split(separator: ".")
        if let last = parts.last {
            return String(last)
        }
        return bundleID
    }
}

// MARK: - Running App Model

private struct RunningApp: Identifiable {
    let id = UUID()
    let bundleID: String
    let name: String
    let icon: NSImage?
}

// MARK: - App Picker Sheet

private struct AppPickerSheet: View {
    let availableApps: [RunningApp]
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Chọn ứng dụng")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(availableApps) { app in
                        Button {
                            onSelect(app.bundleID)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                if let icon = app.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.primary.opacity(0.1))
                                        .frame(width: 32, height: 32)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(app.bundleID)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.blue)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if app.id != availableApps.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(width: 400, height: 500)
    }
}
