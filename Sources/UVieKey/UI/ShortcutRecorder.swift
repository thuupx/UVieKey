import SwiftUI
import AppKit
import Carbon

/// A button that captures the next key combination as a `HotkeyBinding`.
/// Click to enter recording mode, press a shortcut, and the binding is saved
/// via `GlobalHotkeyManager`.
///
/// Two recording modes:
/// - **Key combo** (⌘⇧N): a keyDown with modifiers saves immediately.
/// - **Modifier-only chord** (issue #14): hold only modifier keys (e.g. ⌘⇧)
///   and click "Xong" — no letter key required. The live preview shows the
///   held modifiers; the chord fires when the modifiers are tapped (pressed
///   and released with no other key in between), detected in the event tap.
struct ShortcutRecorder: View {
    @StateObject private var hotkeyManager = GlobalHotkeyManager.shared
    @State private var isRecording = false
    @State private var monitor: Any?
    /// Modifiers held right now (live preview while recording).
    @State private var currentModifiers: NSEvent.ModifierFlags = []
    /// Last non-empty modifier set seen while recording — survives release,
    /// so the user can let go of the keys before clicking "Xong".
    @State private var lastHeldModifiers: NSEvent.ModifierFlags = []

    /// The four chord modifiers a binding can be made of.
    private static let chordMask: NSEvent.ModifierFlags = [.command, .control, .option, .shift]

    /// The chord the user is (or was last) holding while recording.
    private var recordedChord: NSEvent.ModifierFlags {
        let live = currentModifiers.intersection(Self.chordMask)
        return live.isEmpty ? lastHeldModifiers : live
    }

    private var chordSymbols: String {
        let m = recordedChord
        var s = ""
        if m.contains(.control) { s += "⌃" }
        if m.contains(.option)  { s += "⌥" }
        if m.contains(.shift)   { s += "⇧" }
        if m.contains(.command) { s += "⌘" }
        return s
    }

    var body: some View {
        HStack(spacing: 8) {
            if isRecording {
                Text(chordSymbols.isEmpty ? "Nhấn phím tắt…" : "\(chordSymbols) …")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
                    )
            } else if let binding = hotkeyManager.binding {
                Text(binding.displayString)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            } else {
                Text("Chưa đặt")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }

            Button {
                if isRecording {
                    confirmRecording()
                } else {
                    startRecording()
                }
            } label: {
                Text(isRecording ? "Xong" : "Đặt phím")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isRecording && chordSymbols.isEmpty)

            if isRecording {
                Button {
                    stopRecording()
                } label: {
                    Text("Huỷ")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if hotkeyManager.binding != nil && !isRecording {
                Button {
                    hotkeyManager.clearBinding()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Xoá phím tắt")
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        guard monitor == nil else { return }
        isRecording = true
        currentModifiers = []
        lastHeldModifiers = []

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                // Track the held modifiers for the live preview and the
                // Done button — a modifier-only chord has no keyDown.
                let live = event.modifierFlags.intersection(Self.chordMask)
                currentModifiers = live
                if !live.isEmpty {
                    lastHeldModifiers = live
                }
                return event
            }

            // Escape cancels recording.
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            if let binding = HotkeyBinding(from: event) {
                hotkeyManager.setBinding(binding)
                stopRecording()
                // Consume the event so it doesn't propagate.
                return nil
            }
            // No modifier held — ignore but keep recording.
            return event
        }
    }

    /// Saves the recorded modifier-only chord (Done button). No-op save when
    /// no modifier was ever held — recording just stops.
    private func confirmRecording() {
        let chord = recordedChord
        if !chord.isEmpty {
            var carbon = 0
            if chord.contains(.command) { carbon |= cmdKey }
            if chord.contains(.shift)   { carbon |= shiftKey }
            if chord.contains(.option)  { carbon |= optionKey }
            if chord.contains(.control) { carbon |= controlKey }
            hotkeyManager.setBinding(
                HotkeyBinding(keyCode: HotkeyBinding.modifierOnlyKeyCode, modifiers: carbon)
            )
        }
        stopRecording()
    }

    private func stopRecording() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        isRecording = false
        currentModifiers = []
        lastHeldModifiers = []
    }
}
