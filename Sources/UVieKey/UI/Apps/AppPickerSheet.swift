import SwiftUI
import AppKit

// MARK: - App Picker Sheet

struct AppPickerSheet: View {
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
