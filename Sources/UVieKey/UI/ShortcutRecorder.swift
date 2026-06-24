import SwiftUI
import AppKit

/// A button that captures the next key combination (with modifiers) as a
/// `HotkeyBinding`. Click to enter recording mode, press a shortcut, and the
/// binding is saved via `GlobalHotkeyManager`.
struct ShortcutRecorder: View {
    @StateObject private var hotkeyManager = GlobalHotkeyManager.shared
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            if isRecording {
                Text("Nhấn phím tắt…")
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
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                Text(isRecording ? "Huỷ" : "Đặt phím")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

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

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
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

    private func stopRecording() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        isRecording = false
    }
}
