import SwiftUI

// MARK: - Popover View

struct MenuBarPopoverView: View {
    @ObservedObject var controller: MenuBarController
    @StateObject private var updateChecker = UpdateChecker.shared
    @AppStorage(DefaultsKey.inputMethod)        private var inputMethod: String = "telex"
    @AppStorage(DefaultsKey.smartSwitchKey)     private var smartSwitchKey: Bool = true
    @AppStorage(DefaultsKey.uppercaseFirstChar) private var uppercaseFirstChar: Bool = false
    @AppStorage(DefaultsKey.macroEnabled)       private var macroEnabled: Bool = false
    @AppStorage(DefaultsKey.relaxedCoda)        private var relaxedCoda: Bool = false
    @AppStorage(DefaultsKey.autoDisableOnNonLatinLayout) private var autoDisableOnNonLatinLayout: Bool = true
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
            popoverFooter
        }
        .frame(width: 280)
    }

    // MARK: Header

    private var popoverHeader: some View {
        HStack(spacing: 8) {
            Text("UVieKey")
                .font(.system(size: 13, weight: .semibold))
            if updateChecker.hasUpdate {
                Text("Có cập nhật")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())
            }
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
            toggleRow("g.circle",                    "Viết tắt g→ng, h→nh",      $relaxedCoda)
            toggleRow("doc.text",                    "Macro văn bản",            $macroEnabled)

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
