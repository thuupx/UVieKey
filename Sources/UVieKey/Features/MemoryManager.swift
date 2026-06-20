import Foundation
import Cocoa
import Combine

/// Per-app language/input-method memory.
/// Stores a map of bundleID → packed state (language | codeTable) in NSUserDefaults.
final class MemoryManager: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            guard !isUpdatingFromObserver else { return }
            save()
        }
    }

    /// Packed: lower bit = language (0=EN, 1=VN), next bits = codeTable
    private var stateMap: [String: Int] = [:]
    private let defaultsKey = "smartSwitchKeyStateMap_v1"
    private var cancellables = Set<AnyCancellable>()
    private var isUpdatingFromObserver = false

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.smartSwitchKey)
        load()
        observeSettingsChanges()
    }

    private func observeSettingsChanges() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .map { _ in UserDefaults.standard.bool(forKey: DefaultsKey.smartSwitchKey) }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newEnabled in
                guard let self, self.isEnabled != newEnabled else { return }
                self.isUpdatingFromObserver = true
                self.isEnabled = newEnabled
                self.isUpdatingFromObserver = false
            }
            .store(in: &cancellables)
    }

    deinit {
        cancellables.removeAll()
    }

    // MARK: - Query / Update

    func state(for bundleID: String) -> (language: Bool, codeTable: Int)? {
        guard isEnabled, let packed = stateMap[bundleID] else { return nil }
        let language = (packed & 0x01) != 0
        let codeTable = (packed >> 1) & 0x07
        return (language, codeTable)
    }

    func setState(language: Bool, codeTable: Int = 0, for bundleID: String) {
        guard isEnabled else { return }
        let packed = (language ? 1 : 0) | ((codeTable & 0x07) << 1)
        stateMap[bundleID] = packed
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            loadLegacy()
            return
        }
        do {
            let decoded = try JSONDecoder().decode([String: Int].self, from: data)
            stateMap = decoded
        } catch {
            stateMap = [:]
        }
    }

    private func save() {
        UserDefaults.standard.set(isEnabled, forKey: DefaultsKey.smartSwitchKey)
        guard !stateMap.isEmpty else {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            return
        }
        do {
            let data = try JSONEncoder().encode(stateMap)
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } catch {
            // Silently ignore encoding errors
        }
    }

    private func loadLegacy() {
        guard let legacyData = UserDefaults.standard.data(forKey: "smartSwitchKey") else { return }
        var cursor = 0
        guard legacyData.count >= 2 else { return }
        let count = UInt16(legacyData[cursor]) | (UInt16(legacyData[cursor + 1]) << 8)
        cursor += 2

        for _ in 0..<count {
            guard cursor < legacyData.count else { break }
            let bundleLen = Int(legacyData[cursor])
            cursor += 1
            guard cursor + bundleLen <= legacyData.count else { break }
            let bundleData = legacyData[cursor..<cursor + bundleLen]
            cursor += bundleLen
            guard cursor < legacyData.count else { break }
            let value = Int(legacyData[cursor])
            cursor += 1

            if let bundleID = String(data: Data(bundleData), encoding: .utf8) {
                stateMap[bundleID] = value
            }
        }
        // Migrate to JSON format immediately
        save()
    }
}
