import Foundation
import Carbon

/// Monitors keyboard layout changes and notifies when non-Latin layout is active.
/// Used for "Auto-disable on non-Latin layout" feature.
final class KeyboardLayoutMonitor: ObservableObject {
    static let shared = KeyboardLayoutMonitor()

    @Published var isNonLatinLayout: Bool = false

    private var currentSource: TISInputSource?

    private init() {
        checkCurrentLayout()
        startMonitoring()
    }

    /// Check if current keyboard layout is Latin-based
    private func checkCurrentLayout() {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            isNonLatinLayout = false
            return
        }
        currentSource = source
        isNonLatinLayout = !isLatinLayout(source)
    }

    /// Check if input source uses Latin script
    private func isLatinLayout(_ source: TISInputSource) -> Bool {
        // Get the input source ID
        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return true // Default to Latin if can't determine
        }
        let sourceID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String

        // Common Latin-based input sources
        let latinKeywords = [
            "ABC", "US", "UK", "French", "German", "Spanish", "Italian",
            "Portuguese", "Dutch", "Swedish", "Norwegian", "Danish", "Finnish",
            "Polish", "Czech", "Hungarian", "Romanian", "Slovak", "Slovenian",
            "Croatian", "Serbian-Latin", "Estonian", "Latvian", "Lithuanian",
            "Turkish", "Vietnamese", "Telex", "VNI"
        ]

        // Check if source ID contains any Latin keyword
        for keyword in latinKeywords {
            if sourceID.localizedCaseInsensitiveContains(keyword) {
                return true
            }
        }

        // Non-Latin layouts typically contain these keywords
        let nonLatinKeywords = [
            "Chinese", "Japanese", "Korean", "Kotoeri", "Hiragana", "Katakana",
            "Pinyin", "Wubi", "Bopomofo", "Cangjie", "Simplified", "Traditional",
            "Hangul", "Hanja", "Russian", "Greek", "Arabic", "Hebrew", "Thai",
            "Hindi", "Devanagari", "Cyrillic", "Georgian", "Armenian"
        ]

        for keyword in nonLatinKeywords {
            if sourceID.localizedCaseInsensitiveContains(keyword) {
                return false
            }
        }

        // Default: assume Latin for unknown layouts
        return true
    }

    /// Start monitoring keyboard layout changes
    private func startMonitoring() {
        // Distributed notification for input source changes
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged),
            name: .init("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil
        )
    }

    @objc private func inputSourceChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.checkCurrentLayout()
        }
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }
}
