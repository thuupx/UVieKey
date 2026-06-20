import Foundation
import AppKit

@MainActor
final class ClipboardManager: ObservableObject {
    static let shared = {
        // Ensure initialization on main thread
        if Thread.isMainThread {
            return ClipboardManager()
        } else {
            return DispatchQueue.main.sync {
                ClipboardManager()
            }
        }
    }()

    @Published private(set) var history: [String] = []
    @Published private(set) var recentlyCopiedString: String?

    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private var isCopyingFromHistory = false
    private var clearCopiedTimer: Timer?

    private let defaultsKey = "ClipboardHistory"
    private let previewCount = 5

    private var maxHistoryCount: Int {
        let stored = UserDefaults.standard.integer(forKey: DefaultsKey.clipboardMaxEntries)
        let value = stored > 0 ? stored : 10
        return min(value, 99)
    }

    var previewItems: [String] {
        Array(history.prefix(previewCount))
    }

    private init() {
        loadHistory()
        enforceLimit()
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func startObserving() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.checkPasteboard()
            }
        }
    }

    func stopObserving() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - History

    private func checkPasteboard() {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.clipboardHistoryEnabled) else { return }

        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        // Something new was copied externally - clear the "copied" indicator
        if !isCopyingFromHistory {
            recentlyCopiedString = nil
        }

        guard !isCopyingFromHistory,
              let string = pasteboard.string(forType: .string),
              !string.isEmpty else { return }

        let autoSplit = UserDefaults.standard.bool(forKey: DefaultsKey.clipboardAutoSplitEnabled)

        if autoSplit {
            let delimiter = UserDefaults.standard.string(forKey: DefaultsKey.clipboardSplitDelimiter) ?? "newline"
            let minLength = UserDefaults.standard.integer(forKey: DefaultsKey.clipboardSplitMinLength)
            let effectiveMinLength = minLength > 0 ? minLength : 3

            let segments = split(string, by: delimiter)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.count >= effectiveMinLength }

            if segments.count > 1 {
                for segment in segments.reversed() {
                    history.removeAll { $0 == segment }
                    history.insert(segment, at: 0)
                }
                enforceLimit()
                saveHistory()
                return
            }
        }

        if history.first == string { return }

        history.removeAll { $0 == string }
        history.insert(string, at: 0)
        enforceLimit()
        saveHistory()
    }

    private func split(_ string: String, by delimiter: String) -> [String] {
        switch delimiter {
        case "newline":
            return string.components(separatedBy: .newlines)
        case "comma":
            return string.components(separatedBy: ",")
        case "semicolon":
            return string.components(separatedBy: ";")
        default:
            return string.components(separatedBy: delimiter)
        }
    }

    private func enforceLimit() {
        if history.count > maxHistoryCount {
            history = Array(history.prefix(maxHistoryCount))
        }
    }

    func copyToClipboard(_ string: String) {
        isCopyingFromHistory = true
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        lastChangeCount = pasteboard.changeCount

        recentlyCopiedString = string
        clearCopiedTimer?.invalidate()
        clearCopiedTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.recentlyCopiedString = nil
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isCopyingFromHistory = false
        }
    }

    func remove(at index: Int) {
        guard history.indices.contains(index) else { return }
        history.remove(at: index)
        saveHistory()
    }

    func clearHistory() {
        guard !history.isEmpty else { return }
        history.removeAll()
        saveHistory()
    }

    // MARK: - Persistence

    private func loadHistory() {
        if let stored = UserDefaults.standard.object(forKey: defaultsKey) as? [String] {
            history = stored
        }
    }

    private func saveHistory() {
        UserDefaults.standard.set(history, forKey: defaultsKey)
    }
}
