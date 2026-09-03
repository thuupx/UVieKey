import Foundation
import os

/// Centralized logging for UVieKey.
///
/// - Uses `os.Logger` for structured system logs (visible in Console.app).
/// - Also writes a rolling file log at `~/Library/Logs/UVieKey/uviekey.log`
///   (1 MB rotate, keep 3 archives) so users can send diagnostics without
///   needing Console.app.
/// - A keystroke trace mode (off by default) logs every `feed`/`backspace`/
///   `commit` call with the engine state, which powers bug reproduction
///   reports (Bug #3 + #4).
final class Logger {
    static let shared = Logger()

    private let osLogger = os.Logger(subsystem: "com.thuupx.UVieKey", category: "engine")

    private let logQueue = DispatchQueue(label: "com.thuupx.UVieKey.logger", qos: .utility)
    private let maxFileSize: Int = 1_048_576 // 1 MB
    private let maxArchives = 3
    private let logURL: URL
    private var fileHandle: FileHandle?
    private var currentSize: Int = 0
    private var defaultsObserver: NSObjectProtocol?

    /// UserDefaults key for the keystroke trace toggle (Settings → Nâng cao).
    static let keystrokeTraceKey = "KeystrokeTraceEnabled"

    /// Cached keystroke-trace toggle. `keystroke()` runs on every keystroke
    /// from the event-tap callback — a UserDefaults read there is disk-backed
    /// and can stall the tap. The cache is refreshed on
    /// `didChangeNotification` (the Settings toggle writes via @AppStorage
    /// in-process, so the notification always fires on the main thread).
    private var traceEnabledCache = false

    /// When true, every feed/backspace/commit call is logged with engine state.
    /// Off by default — only enabled on user request for bug reproduction.
    var keystrokeTraceEnabled: Bool {
        traceEnabledCache
    }

    private init() {
        traceEnabledCache = UserDefaults.standard.bool(forKey: Self.keystrokeTraceKey)

        if let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            let logsDir = libraryDir.appending(path: "Logs/UVieKey")
            try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
            logURL = logsDir.appending(path: "uviekey.log")
        } else {
            // Fallback to tmp if the user library directory is unavailable.
            logURL = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "uviekey.log")
        }

        // Registered after all stored properties are initialized — the closure
        // captures `self`, which is only valid once init completes.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.traceEnabledCache = UserDefaults.standard.bool(forKey: Self.keystrokeTraceKey)
        }

        // File handle is opened lazily on the first write (see `writeLine`),
        // so when diagnostics are off we never create `uviekey.log` on disk.
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        try? fileHandle?.close()
    }

    // MARK: - Public logging API

    func info(_ message: String) { log(message, level: "INFO") }
    func warn(_ message: String) { log(message, level: "WARN") }
    func error(_ message: String) { log(message, level: "ERROR") }
    func debug(_ message: String) { log(message, level: "DEBUG") }

    /// Log a keystroke trace line. Only writes if `keystrokeTraceEnabled` is true.
    /// Kept on a dedicated queue so the event-tap thread never blocks on disk I/O.
    func keystroke(_ message: String) {
        // `keystrokeTraceEnabled` is a cached flag — no UserDefaults read on
        // the hot path. Callers on the event-tap callback should additionally
        // gate the message construction behind this flag.
        guard keystrokeTraceEnabled else { return }
        log(message, level: "TRACE", fileLoggingForced: true)
    }

    // MARK: - Collection

    /// Collects the current log + perf log + system profile into a single
    /// string. The caller writes it to a temp `.txt` and reveals it in Finder
    /// (see `writeDiagnosticsToTempFile`) — `NSSharingServicePicker` was
    /// dropped after the macOS 26 over-release crash.
    func collectDiagnostics() -> String {
        var parts: [String] = []

        parts.append("=== UVieKey Diagnostics ===")
        parts.append("Generated: \(ISO8601DateFormatter().string(from: Date.now))")
        parts.append("App version: \(AppVersion.fullVersion)")
        parts.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        parts.append("Input method: \(UserDefaults.standard.string(forKey: DefaultsKey.inputMethod) ?? "telex")")
        parts.append("Modern orthography: \(UserDefaults.standard.bool(forKey: DefaultsKey.modernOrthography))")
        parts.append("Relaxed coda: \(UserDefaults.standard.bool(forKey: DefaultsKey.relaxedCoda))")
        parts.append("Quick telex: \(UserDefaults.standard.bool(forKey: DefaultsKey.quickTelex))")
        parts.append("Quick start: \(UserDefaults.standard.bool(forKey: DefaultsKey.quickStart))")
        parts.append("Uppercase first: \(UserDefaults.standard.bool(forKey: DefaultsKey.uppercaseFirstChar))")
        parts.append("Auto disable non-Latin: \(UserDefaults.standard.bool(forKey: DefaultsKey.autoDisableOnNonLatinLayout))")
        parts.append("Keystroke trace: \(keystrokeTraceEnabled)")
        parts.append("")

        parts.append("=== uviekey.log (current) ===")
        if let data = try? Data(contentsOf: logURL), let s = String(data: data, encoding: .utf8) {
            // Tail the last 200 KB to keep the report manageable.
            let tail = s.count > 204_800 ? String(s.suffix(204_800)) : s
            parts.append(tail)
        } else {
            parts.append("(no log file)")
        }
        parts.append("")

        parts.append("=== uviekey_perf.log ===")
        let perfURL = URL(fileURLWithPath: "/tmp/uviekey_perf.log")
        if let data = try? Data(contentsOf: perfURL), let s = String(data: data, encoding: .utf8) {
            let tail = s.count > 100_000 ? String(s.suffix(100_000)) : s
            parts.append(tail)
        } else {
            parts.append("(no perf log)")
        }

        return parts.joined(separator: "\n")
    }

    /// Write diagnostics to a temp `.txt` and return its URL for sharing.
    func writeDiagnosticsToTempFile() -> URL? {
        let content = collectDiagnostics()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("UVieKey-diagnostics-\(Int(Date.now.timeIntervalSince1970)).txt")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            Self.shared.error("Failed to write diagnostics: \(error)")
            return nil
        }
    }

    // MARK: - Internal

    private func log(_ message: String, level: String, fileLoggingForced: Bool = false) {
        // Mirror to os.Logger so Console.app picks it up too. This is always
        // on — Console.app is opt-in on the user side, so it never produces
        // surprise files on disk.
        switch level {
        case "ERROR": osLogger.error("\(message, privacy: .public)")
        case "WARN":  osLogger.warning("\(message, privacy: .public)")
        case "INFO":  osLogger.info("\(message, privacy: .public)")
        default:      osLogger.debug("\(message, privacy: .public)")
        }

        // File logging is gated behind the "Bật chẩn đoán" toggle
        // (Settings → Năng cao). When diagnostics are off, no `uviekey.log`
        // file is written — avoiding unbounded disk writes during normal use.
        // `fileLoggingForced` lets callers that already checked the toggle
        // skip the second UserDefaults read.
        guard fileLoggingForced || keystrokeTraceEnabled else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date.now)
        let line = "\(timestamp) [\(level)] \(message)\n"

        logQueue.async { [weak self] in
            self?.writeLine(line)
        }
    }

    private func writeLine(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        // Open the file handle lazily on the first write. This keeps
        // `uviekey.log` off disk entirely when diagnostics are off.
        if fileHandle == nil {
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            } else if let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
                      let size = attrs[.size] as? Int {
                currentSize = size
            }
            fileHandle = try? FileHandle(forWritingTo: logURL)
            _ = try? fileHandle?.seekToEnd()
        }
        currentSize += data.count
        if currentSize > maxFileSize {
            rotate()
        }
        _ = try? fileHandle?.seekToEnd()
        try? fileHandle?.write(contentsOf: data)
    }

    private func rotate() {
        try? fileHandle?.close()
        fileHandle = nil

        // Shift archives: .3 -> .2 -> .1, current -> .1
        for i in stride(from: maxArchives - 1, through: 1, by: -1) {
            let from = URL(fileURLWithPath: logURL.path + ".\(i)")
            let to = URL(fileURLWithPath: logURL.path + ".\(i + 1)")
            try? FileManager.default.removeItem(at: to)
            try? FileManager.default.moveItem(at: from, to: to)
        }
        if FileManager.default.fileExists(atPath: logURL.path) {
            try? FileManager.default.moveItem(at: logURL, to: URL(fileURLWithPath: logURL.path + ".1"))
        }

        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: logURL)
        currentSize = 0
    }
}
