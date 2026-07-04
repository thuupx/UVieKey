import SwiftUI

// MARK: - About Pane

struct AboutPane: View {
    @StateObject private var updateChecker = UpdateChecker.shared
    @State private var showBugReportGuide = false

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

                // Update status block
                VStack(spacing: 10) {
                    // In-app update button (Sparkle). When an update is
                    // available, Sparkle shows its own update window with
                    // release notes, download progress, and install button.
                    // The manual download link below serves as fallback.
                    if updateChecker.hasUpdate {
                        Button {
                            UpdateManager.shared.checkForUpdates()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Cập nhật v\(updateChecker.latestVersion ?? "")")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: 260)

                        // Fallback: manual download link if Sparkle fails
                        if let url = updateChecker.latestReleaseURL {
                            Link(destination: url) {
                                Text("Tải thủ công")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    } else if let last = updateChecker.lastChecked {
                        Text("Đã kiểm tra: \(last.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }

                    // Manual "check now" button — triggers Sparkle's check
                    Button {
                        UpdateManager.shared.checkForUpdates()
                    } label: {
                        HStack(spacing: 6) {
                            if updateChecker.isChecking {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            Text(updateChecker.isChecking ? "Đang kiểm tra…" : "Kiểm tra cập nhật")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .frame(maxWidth: 260)
                        .padding(.vertical, 8)
                        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(updateChecker.isChecking)
                }
            }

            Spacer()
            Divider()

            HStack(spacing: 0) {
                aboutLink("link",                  "GitHub",     "https://github.com/thuupx/UVieKey")
                Divider().frame(height: 20)
                bugReportButton
                Divider().frame(height: 20)
                aboutLink("arrow.down.circle",     "Cập nhật",   "https://github.com/thuupx/UVieKey/releases")
            }
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showBugReportGuide) {
            BugReportGuide()
        }
    }

    private var bugReportButton: some View {
        Button { showBugReportGuide = true } label: {
            VStack(spacing: 5) {
                Image(systemName: "exclamationmark.bubble").font(.system(size: 14))
                Text("Báo lỗi").font(.system(size: 11))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func appIconImage() -> NSImage {
        // 1) Try the app bundle's icon (used in packaged .app builds)
        if let bundleIcon = NSImage(named: "AppIcon") {
            return bundleIcon
        }
        // 2) Fall back to the source repo path (used during `swift build` / Xcode run)
        let sourceFile = URL(fileURLWithPath: #file)
        let repoIcon = sourceFile
            .deletingLastPathComponent() // Panes
            .deletingLastPathComponent() // Settings
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
