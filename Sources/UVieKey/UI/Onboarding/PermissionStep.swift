import SwiftUI

// MARK: - Step 1: Permission

struct PermissionStep: View {
    @Binding var isTrusted: Bool
    let onRequest: () -> Void

    private var needsInputMonitoring: Bool { AccessibilityChecker.requiresInputMonitoring }
    private var inputMonitoringTrusted: Bool { AccessibilityChecker.isInputMonitoringTrusted }

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

            // Accessibility status card
            SettingsCard {
                HStack(spacing: 12) {
                    Image(systemName: isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(isTrusted ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isTrusted ? "Trợ năng: đã cấp" : "Trợ năng: chưa cấp")
                            .font(.system(size: 13, weight: .semibold))
                        Text(isTrusted
                             ? "Đã cấp quyền Trợ năng"
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

            // Input Monitoring (macOS 15+ only)
            if needsInputMonitoring {
                SettingsCard {
                    HStack(spacing: 12) {
                        Image(systemName: inputMonitoringTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(inputMonitoringTrusted ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(inputMonitoringTrusted ? "Input Monitoring: đã cấp" : "Input Monitoring: chưa cấp")
                                .font(.system(size: 13, weight: .semibold))
                            Text("macOS 15+ yêu cầu thêm quyền này để bắt phím gõ.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    if !inputMonitoringTrusted {
                        SCardDivider()
                        Button {
                            AccessibilityChecker.openInputMonitoringSettings()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "lock.open")
                                Text("Mở System Settings → Input Monitoring")
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
        }
        .padding(.horizontal, 48)
    }
}
