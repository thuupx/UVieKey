import Foundation

// MARK: - C FFI (UvieEngine - diff-based API)

@_silgen_name("uvie_engine_new")
func uvie_engine_new() -> OpaquePointer?

@_silgen_name("uvie_engine_free")
func uvie_engine_free(_ engine: OpaquePointer?)

@_silgen_name("uvie_engine_reset")
func uvie_engine_reset(_ engine: OpaquePointer?)

@_silgen_name("uvie_engine_set_input_method")
func uvie_engine_set_input_method(_ engine: OpaquePointer?, _ method: Int32)

@_silgen_name("uvie_engine_set_modern_orthography")
func uvie_engine_set_modern_orthography(_ engine: OpaquePointer?, _ enabled: Int32)

@_silgen_name("uvie_engine_feed")
func uvie_engine_feed(_ engine: OpaquePointer?, _ ch: CChar, _ out_buf: UnsafeMutablePointer<CChar>?, _ out_len: Int) -> Int

@_silgen_name("uvie_engine_backspace")
func uvie_engine_backspace(_ engine: OpaquePointer?, _ out_buf: UnsafeMutablePointer<CChar>?, _ out_len: Int) -> Int

@_silgen_name("uvie_engine_commit")
func uvie_engine_commit(_ engine: OpaquePointer?, _ out_buf: UnsafeMutablePointer<CChar>?, _ out_len: Int) -> Int

@_silgen_name("uvie_engine_is_composing")
func uvie_engine_is_composing(_ engine: OpaquePointer?) -> Int32

@_silgen_name("uvie_engine_committed_text")
func uvie_engine_committed_text(_ engine: OpaquePointer?, _ out_buf: UnsafeMutablePointer<CChar>?, _ out_len: Int) -> Int

@_silgen_name("uvie_engine_current_output")
func uvie_engine_current_output(_ engine: OpaquePointer?, _ out_buf: UnsafeMutablePointer<CChar>?, _ out_len: Int) -> Int

@_silgen_name("uvie_engine_raw_chars")
func uvie_engine_raw_chars(_ engine: OpaquePointer?, _ out_buf: UnsafeMutablePointer<CChar>?, _ out_len: Int) -> Int

/// Diff-based Vietnamese input engine wrapper.
/// Returns (backspace_count, new_output) from Rust on each keystroke.
final class EngineBridge {
    private var engine: OpaquePointer?

    var isComposing: Bool {
        guard let engine else { return false }
        return uvie_engine_is_composing(engine) != 0
    }

    init() {
        engine = uvie_engine_new()
    }

    deinit {
        if let engine {
            uvie_engine_free(engine)
        }
    }

    // MARK: - Configuration

    func setInputMethod(_ method: InputMethod) {
        guard let engine else { return }
        uvie_engine_set_input_method(engine, method == .vni ? 1 : 0)
    }

    func setModernOrthography(_ enabled: Bool) {
        guard let engine else { return }
        uvie_engine_set_modern_orthography(engine, enabled ? 1 : 0)
    }

    // MARK: - Keystroke handling

    /// Feed a single character. Returns (backspaces, new_output).
    /// The Rust engine tracks uppercase via the raw key byte, so we must pass
    /// the original ASCII byte (e.g., 'A' stays 'A') instead of lowercasing it.
    func feed(char: Character) -> (Int, String) {
        guard let engine else { return (0, "") }
        var buf = [CChar](repeating: 0, count: 128)
        // Only ASCII keys are feedable; non-ASCII passes 0 which the engine ignores.
        let byte = CChar(char.asciiValue ?? 0)
        let bs = uvie_engine_feed(engine, byte, &buf, buf.count)
        return (bs, String(cString: buf))
    }

    /// Backspace. Returns (backspaces, new_output).
    func backspace() -> (Int, String) {
        guard let engine else { return (0, "") }
        var buf = [CChar](repeating: 0, count: 128)
        let bs = uvie_engine_backspace(engine, &buf, buf.count)
        return (bs, String(cString: buf))
    }

    func commit() -> (Int, String) {
        guard let engine else { return (0, "") }
        var buf = [CChar](repeating: 0, count: 128)
        let bs = uvie_engine_commit(engine, &buf, buf.count)
        return (bs, String(cString: buf))
    }

    func reset() {
        guard let engine else { return }
        uvie_engine_reset(engine)
    }

    func committedText() -> String {
        guard let engine else { return "" }
        var buf = [CChar](repeating: 0, count: 128)
        _ = uvie_engine_committed_text(engine, &buf, buf.count)
        return String(cString: buf)
    }
    
    func currentOutput() -> String {
        guard let engine else { return "" }
        var buf = [CChar](repeating: 0, count: 128)
        _ = uvie_engine_current_output(engine, &buf, buf.count)
        return String(cString: buf)
    }

    func rawChars() -> String {
        guard let engine else { return "" }
        var buf = [CChar](repeating: 0, count: 128)
        _ = uvie_engine_raw_chars(engine, &buf, buf.count)
        return String(cString: buf)
    }
}

enum InputMethod: String, CaseIterable, Identifiable {
    case telex
    case vni
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .telex: return "Telex"
        case .vni: return "VNI"
        }
    }
}
