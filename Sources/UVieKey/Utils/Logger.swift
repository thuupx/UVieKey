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

    /// UserDefaults key for the keystroke trace toggle (Settings → Nâng cao).
    static let keystrokeTraceKey = "KeystrokeTraceEnabled"

    /// When true, every feed/backspace/commit call is logged with engine state.
    /// Off by default — only enabled on user request for bug reproduction.
    var keystrokeTraceEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.keystrokeTraceKey)
    }

    private init() {
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/UVieKey", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        logURL = logsDir.appendingPathComponent("uviekey.log")

        // `FileHandle(forWritingTo:)` fails if the file doesn't exist, so
        // create it explicitly first.
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
           let size = attrs[.size] as? Int {
            currentSize = size
        }
        fileHandle = try? FileHandle(forWritingTo: logURL)
        _ = try? fileHandle?.seekToEnd()
    }

    // MARK: - Public logging API

    func info(_ message: String) { log(message, level: "INFO") }
    func warn(_ message: String) { log(message, level: "WARN") }
    func error(_ message: String) { log(message, level: "ERROR") }
    func debug(_ message: String) { log(message, level: "DEBUG") }

    /// Log a keystroke trace line. Only writes if `keystrokeTraceEnabled` is true.
    /// Kept on a dedicated queue so the event-tap thread never blocks on disk I/O.
    func keystroke(_ message: String) {
        guard keystrokeTraceEnabled else { return }
        log(message, level: "TRACE")
    }

    // MARK: - Collection

    /// Collects the last 24h of logs + perf log + system profile into a single
    /// string suitable for sharing via `NSSharingServicePicker`.
    func collectDiagnostics() -> String {
        var parts: [String] = []

        parts.append("=== UVieKey Diagnostics ===")
        parts.append("Generated: \(ISO8601DateFormatter().string(from: Date()))")
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
            .appendingPathComponent("UVieKey-diagnostics-\(Int(Date().timeIntervalSince1970)).txt")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            Self.shared.error("Failed to write diagnostics: \(error)")
            return nil
        }
    }

    // MARK: - Internal

    private func log(_ message: String, level: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) [\(level)] \(message)\n"

        // Mirror to os.Logger so Console.app picks it up too.
        switch level {
        case "ERROR": osLogger.error("\(message, privacy: .public)")
        case "WARN":  osLogger.warning("\(message, privacy: .public)")
        case "INFO":  osLogger.info("\(message, privacy: .public)")
        default:      osLogger.debug("\(message, privacy: .public)")
        }

        logQueue.async { [weak self] in
            self?.writeLine(line)
        }
    }

    private func writeLine(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
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
