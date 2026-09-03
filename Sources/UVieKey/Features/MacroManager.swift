import Foundation
import Combine

/// Manages text macros: abbreviation → expansion mapping.
final class MacroManager: ObservableObject {
    static let shared = MacroManager()
    
    @Published var macros: [Macro] = []
    
    private let macrosKey = "Macros"
    /// Cached `macroEnabled` toggle. `isEnabled()` runs on every Space/break
    /// key from the event-tap callback — a UserDefaults read there is
    /// disk-backed and can stall the tap. Refreshed on `didChangeNotification`
    /// (the Settings/Popover toggles write via @AppStorage in-process).
    /// Internal so tests can pin the toggle without touching real defaults.
    var enabledCache = false
    private var defaultsObserver: NSObjectProtocol?
    
    struct Macro: Identifiable, Codable {
        let id: UUID
        var abbreviation: String
        var expansion: String
        
        init(abbreviation: String, expansion: String) {
            self.id = UUID()
            self.abbreviation = abbreviation
            self.expansion = expansion
        }
    }
    
    private init() {
        loadMacros()
        enabledCache = UserDefaults.standard.bool(forKey: DefaultsKey.macroEnabled)
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.enabledCache = UserDefaults.standard.bool(forKey: DefaultsKey.macroEnabled)
        }
    }
    
    // MARK: - Persistence
    
    private func loadMacros() {
        guard let data = UserDefaults.standard.data(forKey: macrosKey),
              let decoded = try? JSONDecoder().decode([Macro].self, from: data) else {
            macros = []
            return
        }
        macros = decoded
    }
    
    private func saveMacros() {
        guard let encoded = try? JSONEncoder().encode(macros) else { return }
        UserDefaults.standard.set(encoded, forKey: macrosKey)
    }
    
    // MARK: - CRUD
    
    func addMacro(abbreviation: String, expansion: String) {
        let macro = Macro(abbreviation: abbreviation, expansion: expansion)
        macros.append(macro)
        saveMacros()
    }
    
    func updateMacro(_ macro: Macro) {
        if let index = macros.firstIndex(where: { $0.id == macro.id }) {
            macros[index] = macro
            saveMacros()
        }
    }
    
    func deleteMacro(_ macro: Macro) {
        macros.removeAll { $0.id == macro.id }
        saveMacros()
    }
    
    // MARK: - Lookup
    
    func findExpansion(for abbreviation: String) -> String? {
        macros.first { $0.abbreviation == abbreviation }?.expansion
    }
    
    func isEnabled() -> Bool {
        enabledCache
    }
}