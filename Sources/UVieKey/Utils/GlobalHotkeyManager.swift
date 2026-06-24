import Carbon
import Cocoa

/// Stores a keyboard shortcut as a key code + Carbon modifier flags.
struct HotkeyBinding: Equatable, Codable {
    var keyCode: Int
    var modifiers: Int  // Carbon modifier flags (cmdKey, shiftKey, optionKey, controlKey)

    /// Returns true when at least one modifier and a valid key code are set.
    var isValid: Bool {
        keyCode >= 0 && modifiers != 0
    }

    /// Human-readable description, e.g. "⌘⇧V".
    var displayString: String {
        guard isValid else { return "Chưa đặt" }
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey != 0  { s += "⌥" }
        if modifiers & shiftKey != 0   { s += "⇧" }
        if modifiers & cmdKey != 0     { s += "⌘" }
        s += HotkeyBinding.keyName(for: keyCode)
        return s
    }

    static func keyName(for keyCode: Int) -> String {
        // Map common key codes to readable labels.
        switch keyCode {
        case 0:  return "A"
        case 1:  return "S"
        case 2:  return "D"
        case 3:  return "F"
        case 4:  return "H"
        case 5:  return "G"
        case 6:  return "Z"
        case 7:  return "X"
        case 8:  return "C"
        case 9:  return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "5"
        case 23: return "6"
        case 24: return "7"
        case 25: return "8"
        case 26: return "9"
        case 27: return "0"
        case 28: return "-"
        case 29: return "="
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "Return"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "Tab"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "⌫"
        case 53: return "Esc"
        case 122: return "F1"
        case 120: return "F2"
        case 99:  return "F3"
        case 118: return "F4"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:  return "Key\(keyCode)"
        }
    }
}

/// Registers a system-wide hotkey via the Carbon `RegisterEventHotKey` API
/// and invokes `onTrigger` on the main thread when the shortcut is pressed.
@MainActor
final class GlobalHotkeyManager: ObservableObject {
    static let shared = GlobalHotkeyManager()

    /// The currently registered binding (or `nil` if none).
    @Published private(set) var binding: HotkeyBinding?
    /// Whether the hotkey is currently enabled and registered.
    @Published private(set) var isRegistered: Bool = false

    /// Called on the main thread when the user presses the registered shortcut.
    var onTrigger: (() -> Void)?

    private var hotkeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    private init() {
        loadFromDefaults()
    }

    // MARK: - Public API

    /// Loads the saved binding from UserDefaults and registers it if enabled.
    func loadFromDefaults() {
        let defaults = UserDefaults.standard
        let enabled = defaults.bool(forKey: DefaultsKey.customToggleEnabled)
        let keyCode = defaults.integer(forKey: DefaultsKey.customToggleKeyCode)
        let modifiers = defaults.integer(forKey: DefaultsKey.customToggleModifiers)

        if keyCode > 0 && modifiers > 0 {
            binding = HotkeyBinding(keyCode: keyCode, modifiers: modifiers)
        } else {
            binding = nil
        }

        if enabled, let b = binding, b.isValid {
            register(b)
        } else {
            unregister()
        }
    }

    /// Saves a new binding to UserDefaults and (re)registers the hotkey.
    func setBinding(_ newBinding: HotkeyBinding, enabled: Bool = true) {
        let defaults = UserDefaults.standard
        defaults.set(newBinding.keyCode, forKey: DefaultsKey.customToggleKeyCode)
        defaults.set(newBinding.modifiers, forKey: DefaultsKey.customToggleModifiers)
        defaults.set(enabled, forKey: DefaultsKey.customToggleEnabled)

        binding = newBinding
        if enabled && newBinding.isValid {
            register(newBinding)
        } else {
            unregister()
        }
    }

    /// Enables or disables the hotkey without clearing the stored binding.
    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.customToggleEnabled)
        if enabled, let b = binding, b.isValid {
            register(b)
        } else {
            unregister()
        }
    }

    /// Clears the stored binding and unregisters.
    func clearBinding() {
        UserDefaults.standard.set(0, forKey: DefaultsKey.customToggleKeyCode)
        UserDefaults.standard.set(0, forKey: DefaultsKey.customToggleModifiers)
        UserDefaults.standard.set(false, forKey: DefaultsKey.customToggleEnabled)
        binding = nil
        unregister()
    }

    // MARK: - Registration

    private func register(_ b: HotkeyBinding) {
        unregister()

        // Install the event handler once.
        installEventHandlerIfNeeded()

        let hotkeyId = EventHotKeyID(signature: OSType(0x55564B59), // "UVKY"
                                     id: 1)
        let result = RegisterEventHotKey(
            UInt32(b.keyCode),
            UInt32(b.modifiers),
            hotkeyId,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if result == noErr {
            isRegistered = true
        } else {
            NSLog("[UVieKey] GlobalHotkey: RegisterEventHotKey failed with \(result)")
            isRegistered = false
        }
    }

    private func unregister() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        isRegistered = false
    }

    // MARK: - Event handler

    private static var sharedEventHandlerInstalled = false

    private func installEventHandlerIfNeeded() {
        guard !GlobalHotkeyManager.sharedEventHandlerInstalled else { return }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.onTrigger?()
                }
                return noErr
            },
            1,
            &spec,
            selfPtr,
            &eventHandler
        )

        GlobalHotkeyManager.sharedEventHandlerInstalled = true
    }
}

// MARK: - NSEvent convenience

extension HotkeyBinding {
    /// Creates a binding from an NSEvent (key down with modifiers).
    init?(from event: NSEvent) {
        guard event.type == .keyDown else { return nil }

        // Convert NSEvent modifier flags to Carbon modifier flags.
        let nsFlags = event.modifierFlags
        var carbonMods = 0
        if nsFlags.contains(.command) { carbonMods |= cmdKey }
        if nsFlags.contains(.shift)   { carbonMods |= shiftKey }
        if nsFlags.contains(.option)  { carbonMods |= optionKey }
        if nsFlags.contains(.control) { carbonMods |= controlKey }

        // Require at least one modifier to avoid registering bare key presses.
        guard carbonMods != 0 else { return nil }

        self.init(keyCode: Int(event.keyCode), modifiers: carbonMods)
    }
}
