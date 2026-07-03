import SwiftUI

// MARK: - Step 2: Ready

struct ReadyStep: View {
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

            // Restart hint — macOS requires a process restart to fully
            // activate the Accessibility grant in some cases (especially
            // 14+ and 26). We prompt the user here so they don't end up
            // with a "running but not typing" state (Bug #6).
            SettingsCard {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24, alignment: .center)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Khởi động lại UVieKey")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Nếu gõ tiếng Việt không hoạt động ngay, hãy thoát và mở lại UVieKey để macOS nhận quyền Trợ năng.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .frame(maxWidth: 380)

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
