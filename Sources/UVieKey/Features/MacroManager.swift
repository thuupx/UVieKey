import Foundation
import Combine

/// Manages text macros: abbreviation → expansion mapping.
final class MacroManager: ObservableObject {
    static let shared = MacroManager()
    
    @Published var macros: [Macro] = []
    
    private let macrosKey = "Macros"
    
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
        UserDefaults.standard.bool(forKey: DefaultsKey.macroEnabled)
    }
}