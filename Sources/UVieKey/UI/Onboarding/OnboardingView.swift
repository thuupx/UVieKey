import SwiftUI

struct OnboardingView: View {
    @AppStorage(DefaultsKey.onboardingCompleted) private var completed: Bool = false
    @State private var step = 0
    @State private var isTrusted = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if completed {
                // Onboarding already done — the WindowGroup auto-opens on
                // every launch, so render nothing and close the stale window.
                Color.clear
                    .frame(width: 0, height: 0)
                    .onAppear { closeOnboardingWindow() }
            } else {
                onboardingContent
            }
        }
    }

    private var onboardingContent: some View {
        VStack(spacing: 0) {
            stepIndicator
            Spacer()
            stepContent
            Spacer()
            navigationBar
        }
        .frame(minWidth: 560, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            isTrusted = AccessibilityChecker.isTrusted
            // Bring the app to front so the onboarding window shows above
            // whatever app the user was in when they launched UVieKey.
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    /// Close the auto-opened onboarding window when onboarding is already done.
    /// SwiftUI's `WindowGroup` opens its window on every launch regardless of
    /// state, so we must manually dismiss it for returning users.
    private func closeOnboardingWindow() {
        // Prefer the native dismiss environment when available (macOS 14+).
        if #available(macOS 14.0, *) {
            dismiss()
            return
        }
        // Fallback: find and close the onboarding NSWindow directly.
        DispatchQueue.main.async {
            for window in NSApp.windows where window.title == "UVieKey Setup" {
                window.close()
            }
        }
    }

    // MARK: Step indicator

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Capsule()
                    .fill(i <= step ? Color.accentColor : Color.primary.opacity(0.12))
                    .frame(width: i == step ? 20 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: step)
            }
        }
        .padding(.top, 28)
    }

    // MARK: Step content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:  WelcomeStep()
        case 1:  PermissionStep(isTrusted: $isTrusted, onRequest: requestAccess)
        default: ReadyStep()
        }
    }

    // MARK: Navigation

    private var navigationBar: some View {
        VStack(spacing: 10) {
            switch step {
            case 0:
                primaryButton("Bắt đầu thiết lập", icon: "arrow.right") {
                    withAnimation(.spring()) { step = 1 }
                    isTrusted = AccessibilityChecker.isTrusted
                }
            case 1:
                primaryButton("Tiếp tục", icon: "arrow.right", disabled: !isTrusted) {
                    withAnimation(.spring()) { step = 2 }
                }
                Button("Quay lại") { withAnimation(.spring()) { step = 0 } }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            default:
                primaryButton("Bắt đầu sử dụng UVieKey", icon: "checkmark") {
                    completed = true
                    NotificationCenter.default.post(name: .onboardingCompleted, object: nil)
                    dismiss()
                }
            }
        }
        .padding(.horizontal, 48)
        .padding(.bottom, 48)
    }

    private func primaryButton(
        _ label: String,
        icon: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label).font(.system(size: 14, weight: .semibold))
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(disabled ? Color.primary.opacity(0.1) : Color.accentColor,
                         in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(disabled ? Color.secondary : .white)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .keyboardShortcut(step == 2 ? .defaultAction : .none)
    }

    private func requestAccess() {
        AccessibilityChecker.requestAccess()
        AccessibilityChecker.pollForAccess(timeout: 60) { granted in
            DispatchQueue.main.async {
                withAnimation(.spring()) { isTrusted = granted }
            }
        }
    }
}
