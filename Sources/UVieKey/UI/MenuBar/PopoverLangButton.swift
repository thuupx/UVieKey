import SwiftUI

// MARK: - Language Button

struct PopoverLangButton: View {
    let label: String
    let flag: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(flag).font(.system(size: 13, weight: .bold))
                Text(label)
                    .font(.system(size: 12, weight: active ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(active ? Color.accentColor : .primary.opacity(0.06),
                         in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(active ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
