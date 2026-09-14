import Combine
import XCTest
@testable import UVieKey

/// Per-app language memory, the input-method manager, and macro CRUD —
/// the feature layer behind the EventTap.
///
/// These modules read/write `UserDefaults.standard` — every test snapshots
/// the keys it touches and restores them in tearDown so the suite never
/// leaks state into the developer's real environment.
final class FeaturesTests: XCTestCase {
    /// Keys the tests (or the managers they construct) read and write.
    private let watchedKeys = [
        "Macros",
        DefaultsKey.macroEnabled,
        "smartSwitchKeyStateMap_v1",
        "smartSwitchKey", // legacy MemoryManager format
        DefaultsKey.smartSwitchKey,
        DefaultsKey.engineEnabled,
    ]
    private var savedDefaults: [String: Any?] = [:]

    override func setUp() {
        super.setUp()
        for key in savedDefaultsKeys {
            savedDefaults[key] = UserDefaults.standard.object(forKey: key)
        }
    }

    override func tearDown() {
        for (key, value) in savedDefaults {
            if let value {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        savedDefaults = [:]
        super.tearDown()
    }

    private let savedDefaultsKeys = [
        "Macros",
        DefaultsKey.macroEnabled,
        "smartSwitchKeyStateMap_v1",
        "smartSwitchKey", // legacy MemoryManager format
        DefaultsKey.smartSwitchKey,
        DefaultsKey.engineEnabled,
    ]

    /// Runs the main queue long enough for `.receive(on: DispatchQueue.main)`
    /// settings observers to deliver.
    private func flushObservers() {
        let exp = expectation(description: "observer delivery")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: 2)
    }

    // MARK: - MemoryManager

    func test_memory_stateRoundTrip_packsLanguageAndCodeTable() {
        let memory = MemoryManager()
        memory.isEnabled = true

        XCTAssertNil(memory.state(for: "com.test.app"), "unknown app has no memory")

        memory.setState(language: true, codeTable: 3, for: "com.test.app")
        XCTAssertEqual(memory.state(for: "com.test.app")?.language, true)
        XCTAssertEqual(memory.state(for: "com.test.app")?.codeTable, 3)

        memory.setState(language: false, for: "com.test.app")
        XCTAssertEqual(memory.state(for: "com.test.app")?.language, false)
        XCTAssertEqual(memory.state(for: "com.test.app")?.codeTable, 0)
    }

    func test_memory_codeTableIsMaskedToThreeBits() {
        let memory = MemoryManager()
        memory.isEnabled = true

        memory.setState(language: true, codeTable: 9, for: "com.test.app")
        XCTAssertEqual(memory.state(for: "com.test.app")?.codeTable, 1, "codeTable is masked to 0...7")
    }

    func test_memory_disabledIgnoresWritesAndReads() {
        let memory = MemoryManager()
        memory.isEnabled = false

        memory.setState(language: true, for: "com.test.app")
        XCTAssertNil(memory.state(for: "com.test.app"), "disabled memory must not store or return state")
    }

    func test_memory_persistsAcrossInstances() {
        let first = MemoryManager()
        first.isEnabled = true
        first.setState(language: true, codeTable: 2, for: "com.test.persist")

        // A fresh instance loads the JSON map from UserDefaults.
        let second = MemoryManager()
        second.isEnabled = true
        let restored = second.state(for: "com.test.persist")
        XCTAssertEqual(restored?.language, true)
        XCTAssertEqual(restored?.codeTable, 2)
    }

    func test_memory_legacyBinaryFormat_migratesToJSON() {
        // Legacy format: [count:u16 LE] then per entry [len:u8][bundle bytes][value:u8].
        var legacy = Data()
        let bundle = Array("com.test.legacy".utf8)
        legacy.append(UInt8(1)) // count low byte
        legacy.append(UInt8(0)) // count high byte
        legacy.append(UInt8(bundle.count))
        legacy.append(contentsOf: bundle)
        legacy.append(UInt8(3)) // packed: language=1, codeTable=1
        UserDefaults.standard.set(legacy, forKey: "smartSwitchKey")
        UserDefaults.standard.removeObject(forKey: "smartSwitchKeyStateMap_v1")

        let memory = MemoryManager()
        memory.isEnabled = true
        let migrated = memory.state(for: "com.test.legacy")
        XCTAssertEqual(migrated?.language, true)
        XCTAssertEqual(migrated?.codeTable, 1)
        // Migrated to the JSON key immediately.
        XCTAssertNotNil(UserDefaults.standard.data(forKey: "smartSwitchKeyStateMap_v1"))
    }

    // MARK: - InputMethodManager

    func test_inputMethod_toggleFlipsAndSyncsDefaults() {
        let manager = InputMethodManager()
        manager.isVietnamese = true

        manager.toggle()
        XCTAssertFalse(manager.isVietnamese)
        XCTAssertEqual(UserDefaults.standard.bool(forKey: DefaultsKey.engineEnabled), false)

        manager.toggle()
        XCTAssertTrue(manager.isVietnamese)
        XCTAssertEqual(UserDefaults.standard.bool(forKey: DefaultsKey.engineEnabled), true)
    }

    func test_inputMethod_externalEngineEnabledChange_syncs() {
        let manager = InputMethodManager()
        manager.isVietnamese = true

        // Another writer (menu bar toggle, settings) flips the default —
        // the manager must follow it.
        UserDefaults.standard.set(false, forKey: DefaultsKey.engineEnabled)
        flushObservers()
        XCTAssertFalse(manager.isVietnamese)
    }

    func test_inputMethod_setVietnameseSameValue_isNoOp() {
        let manager = InputMethodManager()
        manager.isVietnamese = true

        manager.setVietnamese(true)
        XCTAssertTrue(manager.isVietnamese)
    }

    func test_inputMethod_appSwitch_restoresPerAppLanguage() throws {
        guard let finder = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.finder" }) else {
            throw XCTSkip("Finder not running — cannot simulate an app switch")
        }
        let memory = MemoryManager()
        memory.isEnabled = true
        memory.setState(language: false, for: "com.apple.finder")

        let manager = InputMethodManager(memory: memory)
        manager.isVietnamese = true

        // Simulate the workspace activation notification the real flow uses.
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: finder]
        )
        flushObservers()

        XCTAssertEqual(manager.currentAppBundleID, "com.apple.finder")
        XCTAssertFalse(manager.isVietnamese, "app switch must restore the remembered language")
    }

    // MARK: - MacroManager

    func test_macro_addLookupDelete() {
        let original = MacroManager.shared.macros
        defer { MacroManager.shared.macros = original }

        MacroManager.shared.addMacro(abbreviation: "gtn", expansion: "gõ tắt nhanh")
        XCTAssertEqual(MacroManager.shared.findExpansion(for: "gtn"), "gõ tắt nhanh")
        XCTAssertNil(MacroManager.shared.findExpansion(for: "gt"), "exact match only")
        XCTAssertNil(MacroManager.shared.findExpansion(for: "gtnt"), "no prefix matching")

        let macro = MacroManager.shared.macros.last!
        let updated = MacroManager.Macro(id: macro.id, abbreviation: "gtn", expansion: "NEW")
        MacroManager.shared.updateMacro(updated)
        XCTAssertEqual(MacroManager.shared.findExpansion(for: "gtn"), "NEW")

        MacroManager.shared.deleteMacro(updated)
        XCTAssertNil(MacroManager.shared.findExpansion(for: "gtn"))
    }

    func test_macro_addPersistsToDefaults() {
        let original = MacroManager.shared.macros
        defer { MacroManager.shared.macros = original }

        MacroManager.shared.addMacro(abbreviation: "mk", expansion: "mình không")
        let data = UserDefaults.standard.data(forKey: "Macros")
        XCTAssertNotNil(data, "addMacro must persist")
        let decoded = try? JSONDecoder().decode([MacroManager.Macro].self, from: data!)
        XCTAssertEqual(decoded?.count, original.count + 1)
        // The user's real macros may share the store — assert the added one
        // is present rather than asserting on the whole list.
        XCTAssertTrue(decoded?.contains { $0.expansion == "mình không" } ?? false)
    }

    // MARK: - Logger trace cache

    func test_logger_traceCacheFollowsDefaultsChange() {
        let original = UserDefaults.standard.bool(forKey: Logger.keystrokeTraceKey)
        defer { UserDefaults.standard.set(original, forKey: Logger.keystrokeTraceKey) }

        // The keystroke-trace toggle is cached (UserDefaults reads are not
        // allowed on the event-tap hot path) — it must follow the default
        // after the didChangeNotification is delivered.
        UserDefaults.standard.set(true, forKey: Logger.keystrokeTraceKey)
        flushObservers()
        XCTAssertTrue(Logger.shared.keystrokeTraceEnabled)

        UserDefaults.standard.set(false, forKey: Logger.keystrokeTraceKey)
        flushObservers()
        XCTAssertFalse(Logger.shared.keystrokeTraceEnabled)
    }
}
