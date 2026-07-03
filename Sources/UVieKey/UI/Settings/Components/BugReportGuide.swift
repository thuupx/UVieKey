import SwiftUI
import AppKit

// MARK: - Bug Report Guide Dialog

/// Step-by-step dialog that guides the user through collecting diagnostics
/// and filing a GitHub issue. Shown when the user clicks "Báo lỗi" in the
/// About pane.
struct BugReportGuide: View {
    @AppStorage(Logger.keystrokeTraceKey) private var keystrokeTrace: Bool = false
    @State private var diagnosticsCopied = false
    @State private var diagnosticsFileURL: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "ladybug.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Báo lỗi")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Làm theo các bước dưới đây để gửi báo cáo lỗi")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            // Steps
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    StepView(
                        number: 1,
                        title: "Bật chẩn đoán lỗi",
                        description: "Mở tab Nâng cao → bật nút \"Bật chẩn đoán\". Điều này ghi lại mỗi phím gõ để phân tích lỗi.",
                        actionTitle: keystrokeTrace ? "Đã bật ✓" : "Mở tab Nâng cao",
                        actionDisabled: keystrokeTrace,
                        action: { openAdvancedTab() }
                    )

                    StepView(
                        number: 2,
                        title: "Gõ lại từ gây lỗi",
                        description: "Quay lại app đang dùng và gõ lại chính xác từ/câu gây ra lỗi. Mỗi phím sẽ được ghi vào log.",
                        actionTitle: nil,
                        actionDisabled: false,
                        action: nil
                    )

                    StepView(
                        number: 3,
                        title: "Tạo file chẩn đoán",
                        description: "Tạo file .txt chứa log + thông tin hệ thống, sau đó copy nội dung vào clipboard.",
                        actionTitle: diagnosticsCopied ? "Đã copy ✓" : "Tạo & copy log",
                        actionDisabled: diagnosticsCopied,
                        action: { generateAndCopyDiagnostics() }
                    )

                    if let url = diagnosticsFileURL {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(url.lastPathComponent)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Hiện trong Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    }

                    StepView(
                        number: 4,
                        title: "Mở GitHub Issues và dán nội dung",
                        description: "Mở trang GitHub Issues, tạo issue mới và dán (Cmd+V) nội dung log vào ô mô tả.",
                        actionTitle: "Mở GitHub Issues",
                        actionDisabled: false,
                        action: { openGitHubIssues() }
                    )
                }
                .padding(20)
            }

            Divider()

            // Footer
            HStack {
                Button("Đóng") { dismiss() }
                    .font(.system(size: 12))
                Spacer()
                if keystrokeTrace {
                    Button("Tắt chẩn đoán & đóng") {
                        keystrokeTrace = false
                        dismiss()
                    }
                    .font(.system(size: 12, weight: .medium))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 480, height: 520)
    }

    // MARK: - Actions

    private func openAdvancedTab() {
        NotificationCenter.default.post(
            name: .navigateToSettingsTab,
            object: nil,
            userInfo: ["tab": SettingsTab.advanced]
        )
    }

    private func generateAndCopyDiagnostics() {
        guard let url = Logger.shared.writeDiagnosticsToTempFile() else { return }
        diagnosticsFileURL = url
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(content, forType: .string)
            diagnosticsCopied = true
        }
    }

    private func openGitHubIssues() {
        if let url = URL(string: "https://github.com/thuupx/UVieKey/issues/new") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Step View

private struct StepView: View {
    let number: Int
    let title: String
    let description: String
    let actionTitle: String?
    let actionDisabled: Bool
    let action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Step number badge
            ZStack {
                Circle()
                    .fill(actionDisabled ? Color.green.opacity(0.2) : Color.accentColor.opacity(0.15))
                    .frame(width: 26, height: 26)
                if actionDisabled {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.green)
                } else {
                    Text("\(number)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle, let action {
                    Button(action: action) {
                        Text(actionTitle)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(actionDisabled)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Notification for tab navigation

extension Notification.Name {
    static let navigateToSettingsTab = Notification.Name("navigateToSettingsTab")
}
