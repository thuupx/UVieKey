import SwiftUI
import AppKit

// MARK: - App Row

struct AppRow: View {
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

struct RunningApp: Identifiable {
    let id = UUID()
    let bundleID: String
    let name: String
    let icon: NSImage?
}
