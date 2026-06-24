import Foundation

/// Shared default app lists used by both EventTap (engine runtime) and
/// AppsPane (Settings UI). Keeping them in one place prevents drift between
/// what the engine actually uses and what the UI displays/resets to.
enum AppDefaults {
    /// Apps that need the empty-character sentinel before backspace to
    /// invalidate their autocomplete dropdown (Safari, Notes, TextEdit, Mail,
    /// iWork, and all Chromium browsers whose omnibox swallows synthetic
    /// backspaces).
    static let compoundApps: Set<String> = [
        "com.apple.Safari",
        "com.apple.Notes",
        "com.apple.TextEdit",
        "com.apple.mail",
        "com.apple.iWork",
        // Chromium browsers
        "com.google.Chrome",
        "org.chromium.Chromium",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi",
        "company.thebrowser.Browser", // Arc
        "ai.perplexity.comet", // Comet
        "com.openai.atlas", // ChatGPT Atlas
    ]

    /// Chromium-based browsers that need Shift+Left selection + overwrite
    /// (instead of plain backspace) when replacing text, to avoid duplicate
    /// characters in the omnibox.
    static let chromiumBrowsers: Set<String> = [
        "com.google.Chrome",
        "org.chromium.Chromium",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi",
        "company.thebrowser.Browser", // Arc
        "ai.perplexity.comet", // Comet
        "com.openai.atlas", // ChatGPT Atlas
    ]

    /// Apps that bypass IME entirely (system UI, lock screen, etc.).
    static let bypassApps: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.securityagent",
        "com.apple.ScreenSaver.Engine",
        "com.apple.systemuiserver",
    ]

    /// Apps that need Accessibility text injection instead of CGEventTap.
    static let axApps: Set<String> = [
        "com.apple.Spotlight",
    ]
}
