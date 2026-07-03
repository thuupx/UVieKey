import SwiftUI

// MARK: - Keyboard Pane

struct KeyboardPane: View {
    @AppStorage(DefaultsKey.uppercaseFirstChar) private var uppercaseFirstChar: Bool = false
    @AppStorage(DefaultsKey.relaxedCoda) private var relaxedCoda: Bool = false

    var body: some View {
        PaneScroll {
            PaneSection("Vần cuối") {
                SettingsCard {
                    SToggleRow("g.circle",
                                "Viết tắt vần cuối (g→ng, h→nh)",
                                "Bật để gõ đặg, nhàh thay vì đặng, nhành. Tiện khi gõ nhanh.",
                                $relaxedCoda)
                }
            }

            PaneSection("Tự động hóa") {
                SettingsCard {
                    SToggleRow("textformat",
                                "Viết hoa chữ cái đầu câu",
                                "Tự động viết hoa sau dấu chấm hoặc xuống dòng mới",
                                $uppercaseFirstChar)
                }
            }
        }
    }
}
