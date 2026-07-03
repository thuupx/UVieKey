import SwiftUI

// MARK: - Step 0: Welcome

struct WelcomeStep: View {
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
            .deletingLastPathComponent() // Onboarding
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
