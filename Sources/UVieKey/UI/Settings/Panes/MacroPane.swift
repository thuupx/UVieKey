import SwiftUI

// MARK: - Macro Pane

struct MacroPane: View {
    @AppStorage(DefaultsKey.macroEnabled) private var macroEnabled: Bool = false
    @StateObject private var macroManager = MacroManager.shared
    @State private var showingAddSheet = false
    @State private var newAbbreviation = ""
    @State private var newExpansion = ""

    var body: some View {
        PaneScroll {
            PaneSection("Macro văn bản") {
                SettingsCard {
                    SToggleRow("wand.and.rays",
                                "Bật Macro văn bản",
                                "Gõ viết tắt, nhấn Space / Enter để mở rộng thành văn bản đầy đủ",
                                $macroEnabled)
                }
            }

            if macroEnabled {
                PaneSection("Danh sách Macro") {
                    SettingsCard {
                        // Table header
                        HStack {
                            Text("Viết tắt")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 100, alignment: .leading)
                            Text("Văn bản thay thế")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.04))

                        ForEach(macroManager.macros) { macro in
                            SCardDivider()
                            HStack {
                                Text(macro.abbreviation)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.blue)
                                    .frame(width: 100, alignment: .leading)
                                Text(macro.expansion)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Button {
                                    macroManager.deleteMacro(macro)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                        }
                    }

                    HStack {
                        Spacer()
                        Button {
                            showingAddSheet = true
                        } label: {
                            Label("Thêm Macro", systemImage: "plus.circle.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    .sheet(isPresented: $showingAddSheet) {
                        AddMacroSheet(abbreviation: $newAbbreviation, expansion: $newExpansion) {
                            macroManager.addMacro(abbreviation: newAbbreviation, expansion: newExpansion)
                            newAbbreviation = ""
                            newExpansion = ""
                            showingAddSheet = false
                        }
                    }
                }
            }
        }
    }
}
