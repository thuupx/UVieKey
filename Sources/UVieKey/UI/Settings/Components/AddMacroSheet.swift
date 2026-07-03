import SwiftUI

// MARK: - Add Macro Sheet

struct AddMacroSheet: View {
    @Binding var abbreviation: String
    @Binding var expansion: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Thêm Macro mới")
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Viết tắt")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Ví dụ: btw", text: $abbreviation)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Văn bản thay thế")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Ví dụ: by the way", text: $expansion)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
            }

            HStack(spacing: 12) {
                Button("Hủy") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Lưu") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .disabled(abbreviation.isEmpty || expansion.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
