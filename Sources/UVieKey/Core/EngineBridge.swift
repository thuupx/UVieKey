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

@_silgen_name("uvie_engine_set_relaxed_coda")
func uvie_engine_set_relaxed_coda(_ engine: OpaquePointer?, _ enabled: Int32)

@_silgen_name("uvie_engine_set_quick_telex")
func uvie_engine_set_quick_telex(_ engine: OpaquePointer?, _ enabled: Int32)

@_silgen_name("uvie_engine_set_quick_start")
func uvie_engine_set_quick_start(_ engine: OpaquePointer?, _ enabled: Int32)

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

    /// Output buffer capacity for FFI calls (engine output is a single
    /// syllable, well under 128 bytes).
    private static let bufferCapacity = 128
    /// Reusable output buffer for FFI calls. The engine is only touched from
    /// the event-tap callback (main runloop — see `EventTap.startTap`), so a
    /// single scratch buffer avoids a heap alloc + zeroing on every keystroke.
    /// A static constant is passed as the capacity to avoid an exclusive-access
    /// conflict between `&scratch` and `scratch.count` in the same call.
    private var scratch = [CChar](repeating: 0, count: EngineBridge.bufferCapacity)

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
        let code: Int32 = switch method {
        case .telex: 0
        case .vni: 1
        case .simpleTelex: 2
        }
        uvie_engine_set_input_method(engine, code)
    }

    func setModernOrthography(_ enabled: Bool) {
        guard let engine else { return }
        uvie_engine_set_modern_orthography(engine, enabled ? 1 : 0)
    }

    func setRelaxedCoda(_ enabled: Bool) {
        guard let engine else { return }
        uvie_engine_set_relaxed_coda(engine, enabled ? 1 : 0)
    }

    func setQuickTelex(_ enabled: Bool) {
        guard let engine else { return }
        uvie_engine_set_quick_telex(engine, enabled ? 1 : 0)
    }

    func setQuickStart(_ enabled: Bool) {
        guard let engine else { return }
        uvie_engine_set_quick_start(engine, enabled ? 1 : 0)
    }

    // MARK: - Keystroke handling

    /// Feed a single character. Returns (backspaces, new_output).
    /// The Rust engine tracks uppercase via the raw key byte, so we must pass
    /// the original ASCII byte (e.g., 'A' stays 'A') instead of lowercasing it.
    func feed(char: Character) -> (Int, String) {
        guard let engine else { return (0, "") }
        // Only ASCII keys are feedable; non-ASCII passes 0 which the engine ignores.
        let byte = CChar(char.asciiValue ?? 0)
        let bs = uvie_engine_feed(engine, byte, &scratch, Self.bufferCapacity)
        return (bs, String(cString: scratch))
    }

    /// Backspace. Returns (backspaces, new_output).
    func backspace() -> (Int, String) {
        guard let engine else { return (0, "") }
        let bs = uvie_engine_backspace(engine, &scratch, Self.bufferCapacity)
        return (bs, String(cString: scratch))
    }

    func commit() -> (Int, String) {
        guard let engine else { return (0, "") }
        let bs = uvie_engine_commit(engine, &scratch, Self.bufferCapacity)
        return (bs, String(cString: scratch))
    }

    func reset() {
        guard let engine else { return }
        uvie_engine_reset(engine)
    }

    func committedText() -> String {
        guard let engine else { return "" }
        _ = uvie_engine_committed_text(engine, &scratch, Self.bufferCapacity)
        return String(cString: scratch)
    }

    func currentOutput() -> String {
        guard let engine else { return "" }
        _ = uvie_engine_current_output(engine, &scratch, Self.bufferCapacity)
        return String(cString: scratch)
    }

    func rawChars() -> String {
        guard let engine else { return "" }
        _ = uvie_engine_raw_chars(engine, &scratch, Self.bufferCapacity)
        return String(cString: scratch)
    }
}

enum InputMethod: String, CaseIterable, Identifiable {
    case telex
    case vni
    case simpleTelex
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .telex: return "Telex"
        case .vni: return "VNI"
        case .simpleTelex: return "Simple Telex"
        }
    }
}
