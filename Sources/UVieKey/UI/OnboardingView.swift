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
        .padding(.bottom, 36)
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
        VStack(spacing: 28) {
            // App icon
            Image(nsImage: appIconImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .shadow(color: .black.opacity(0.15), radius: 16, y: 8)

            VStack(spacing: 12) {
                Text("Chào mừng đến với UVieKey")
                    .font(.system(size: 28, weight: .bold))

                Text("Bộ gõ Tiếng Việt nhanh, nhẹ và chính xác cho macOS.\nPowered by uvie-rs - Rust engine zero-cost.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .frame(maxWidth: 400)
            }

            // Feature pills
            HStack(spacing: 10) {
                featurePill("bolt",          "Siêu nhanh",    .orange)
                featurePill("checkmark.seal","Chính xác",     .green)
                featurePill("memorychip",    "Siêu nhẹ",      .blue)
            }
        }
        .padding(.horizontal, 48)
    }

    private func featurePill(_ icon: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(color.opacity(0.08), in: Capsule())
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
        return NSImage(size: NSSize(width: 100, height: 100))
    }
}

// MARK: - Step 1: Permission

private struct PermissionStep: View {
    @Binding var isTrusted: Bool
    let onRequest: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            // Icon
            ZStack {
                Circle()
                    .fill(isTrusted ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                    .frame(width: 96, height: 96)
                Image(systemName: isTrusted ? "checkmark.shield.fill" : "lock.shield")
                    .font(.system(size: 42))
                    .foregroundStyle(isTrusted ? .green : .orange)
            }

            VStack(spacing: 12) {
                Text("Quyền Trợ năng")
                    .font(.system(size: 26, weight: .bold))
                Text("UVieKey cần quyền Accessibility để bắt và xử lý phím gõ.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
            }

            // Status card
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(isTrusted ? .green : .orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isTrusted ? "Đã cấp quyền thành công" : "Chưa cấp quyền")
                            .font(.system(size: 13, weight: .semibold))
                        Text(isTrusted
                             ? "UVieKey sẵn sàng hoạt động"
                             : "Nhấn nút bên dưới để mở System Settings")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(16)

                if !isTrusted {
                    Divider()
                    Button(action: onRequest) {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.open")
                            Text("Mở System Settings → Accessibility")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isTrusted ? Color.green.opacity(0.3) : Color.orange.opacity(0.3),
                        lineWidth: 1
                    )
            )
            .frame(maxWidth: 420)
        }
        .padding(.horizontal, 48)
    }
}

// MARK: - Step 2: Ready

private struct ReadyStep: View {
    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 100, height: 100)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.green)
            }

            VStack(spacing: 12) {
                Text("Tất cả đã sẵn sàng!")
                    .font(.system(size: 28, weight: .bold))
                Text("UVieKey đã được thiết lập xong.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
            }

            // Quick tips
            VStack(alignment: .leading, spacing: 10) {
                tipRow("keyboard",              "Nhấn vào icon V/E trên thanh menu hoac Fn để chuyển ngôn ngữ")
                tipRow("gearshape",             "Mở Cài đặt để tuỳ chỉnh bảng mã và tính năng")
                tipRow("arrow.triangle.2.circlepath", "Mode Memory tự động nhớ ngôn ngữ cho từng app")
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor),
                         in: RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: 420)
        }
        .padding(.horizontal, 48)
    }

    private func tipRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.blue)
                .frame(width: 18)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
