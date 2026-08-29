import SwiftUI

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
                        imOption("Simple Telex", "simpleTelex")
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
