import SwiftUI

struct OnboardingView: View {
    @AppStorage(DefaultsKey.onboardingCompleted) private var completed: Bool = false
    @State private var step = 0
    @State private var isTrusted = false

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
            Spacer()
            stepContent
            Spacer()
            navigationBar
        }
        .frame(minWidth: 560, minHeight: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { isTrusted = AccessibilityChecker.isTrusted }
    }

    // MARK: Step indicator

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Capsule()
                    .fill(i <= step ? Color.accentColor : Color.primary.opacity(0.12))
                    .frame(width: i == step ? 20 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: step)
            }
        }
        .padding(.top, 28)
    }

    // MARK: Step content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:  WelcomeStep()
        case 1:  PermissionStep(isTrusted: $isTrusted, onRequest: requestAccess)
        default: ReadyStep()
        }
    }

    // MARK: Navigation

    private var navigationBar: some View {
        VStack(spacing: 10) {
            switch step {
            case 0:
                primaryButton("Bắt đầu thiết lập", icon: "arrow.right") {
                    withAnimation(.spring()) { step = 1 }
                    isTrusted = AccessibilityChecker.isTrusted
                }
            case 1:
                primaryButton("Tiếp tục", icon: "arrow.right", disabled: !isTrusted) {
                    withAnimation(.spring()) { step = 2 }
                }
                Button("Quay lại") { withAnimation(.spring()) { step = 0 } }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            default:
                primaryButton("Bắt đầu sử dụng UVieKey", icon: "checkmark") {
                    completed = true
                    NotificationCenter.default.post(name: .onboardingCompleted, object: nil)
                }
            }
        }
        .padding(.horizontal, 48)
        .padding(.bottom, 48)
    }

    private func primaryButton(
        _ label: String,
        icon: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label).font(.system(size: 14, weight: .semibold))
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(disabled ? Color.primary.opacity(0.1) : Color.accentColor,
                         in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(disabled ? Color.secondary : .white)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .keyboardShortcut(step == 2 ? .defaultAction : .none)
    }

    private func requestAccess() {
        AccessibilityChecker.requestAccess()
        AccessibilityChecker.pollForAccess(timeout: 60) { granted in
            DispatchQueue.main.async {
                withAnimation(.spring()) { isTrusted = granted }
            }
        }
    }
}

// MARK: - Step 0: Welcome

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 22) {
            // App icon
            Image(nsImage: appIconImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 92, height: 92)

            VStack(spacing: 6) {
                Text("Chào mừng bạn đến với UVieKey")
                    .font(.system(size: 26, weight: .bold))
                Text("Bộ gõ tiếng Việt nhanh, nhẹ và chính xác cho macOS.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)

                Text("Powered by uvie-rs — zero-cost Rust engine.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .frame(maxWidth: 360)
            }

            // Feature highlights
            SettingsCard {
                infoRow("bolt",           "Siêu nhanh",    "Xử lý phím gõ tức thì với engine Rust")
                SCardDivider()
                infoRow("checkmark.seal", "Chính xác",     "Bảng mã Telex & VNI chuẩn xác")
                SCardDivider()
                infoRow("memorychip",     "Siêu nhẹ",      "Tiêu tốn tài nguyên gần như bằng không")
            }
            .frame(maxWidth: 380)
        }
        .padding(.horizontal, 48)
    }

    private func infoRow(_ icon: String, _ title: String, _ description: String) -> some View {
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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
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
}

// MARK: - Step 1: Permission

private struct PermissionStep: View {
    @Binding var isTrusted: Bool
    let onRequest: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            // Icon
            Image(systemName: isTrusted ? "checkmark.shield.fill" : "lock.shield")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(isTrusted ? Color.accentColor : .secondary)
                .frame(width: 92, height: 92)

            VStack(spacing: 6) {
                Text("Quyền Trợ năng")
                    .font(.system(size: 22, weight: .bold))
                Text("UVieKey cần quyền Trợ năng để bắt và xử lý phím gõ.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .frame(maxWidth: 360)
            }

            // Status card
            SettingsCard {
                HStack(spacing: 12) {
                    Image(systemName: isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(isTrusted ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isTrusted ? "Đã cấp quyền thành công" : "Chưa cấp quyền")
                            .font(.system(size: 13, weight: .semibold))
                        Text(isTrusted
                             ? "UVieKey sẵn sàng hoạt động"
                             : "Nhấn nút bên dưới để mở cài đặt Trợ năng")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                if !isTrusted {
                    SCardDivider()
                    Button(action: onRequest) {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.open")
                            Text("Mở System Settings → Trợ năng")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 380)
        }
        .padding(.horizontal, 48)
    }
}

// MARK: - Step 2: Ready

private struct ReadyStep: View {
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(Color.accentColor)
                .frame(width: 92, height: 92)

            VStack(spacing: 6) {
                Text("Tất cả đã sẵn sàng!")
                    .font(.system(size: 26, weight: .bold))
                Text("UVieKey đã sẵn sàng để sử dụng.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
            }

            // Quick tips
            SettingsCard {
                tipRow("keyboard",                     "Nhấn biểu tượng V/E trên thanh menu hoặc phím Fn để chuyển ngôn ngữ")
                SCardDivider()
                tipRow("gearshape",                    "Mở Cài đặt để tuỳ chỉnh bảng mã và tính năng")
                SCardDivider()
                tipRow("arrow.triangle.2.circlepath",  "Mode Memory tự động nhớ ngôn ngữ cho từng ứng dụng")
            }
            .frame(maxWidth: 380)
        }
        .padding(.horizontal, 48)
    }

    private func tipRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
