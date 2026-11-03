import Foundation
@testable import MAIOCore
import MAIOKit
import Testing

/// 模拟 WindowServer + 偏好设置。
@MainActor
final class FakeSystemShortcutStore: SystemShortcutStore {
    var defaults: [RawSystemShortcut]
    var preferences: [Int: JSONValue] = [:]
    private(set) var applied: [(Int, Bool)] = []

    init(_ defaults: [RawSystemShortcut]) {
        self.defaults = defaults
    }

    var isAvailable: Bool {
        true
    }

    func readAll() -> [RawSystemShortcut] {
        defaults.map { raw in
            let stored = preferences[raw.id]?.objectValue?["enabled"]?.boolValue
            return RawSystemShortcut(
                id: raw.id, character: raw.character, keyCode: raw.keyCode,
                modifierMask: raw.modifierMask, isEnabled: stored ?? raw.isEnabled,
            )
        }
    }

    func preferenceEntry(for id: Int) -> JSONValue? {
        preferences[id]
    }

    func apply(id: Int, enabled: Bool, entry: JSONValue?) {
        preferences[id] = entry
        applied.append((id, enabled))
    }
}

@MainActor
struct SystemShortcutTests {
    static let fn: UInt32 = 0x800000
    static let ctrl: UInt32 = 0x40000
    // 🌐A（默认启用，偏好设置中无条目）、🌐Q、⌃←（方向键自带 Fn 位）、⌃F2
    static let dock = RawSystemShortcut(id: 210, character: 97, keyCode: 0, modifierMask: fn, isEnabled: true)
    static let quickNote = RawSystemShortcut(id: 190, character: 113, keyCode: 12, modifierMask: fn, isEnabled: true)
    static let space = RawSystemShortcut(id: 79, character: 65535, keyCode: 123, modifierMask: fn | ctrl, isEnabled: true)
    static let menuBar = RawSystemShortcut(id: 7, character: 65535, keyCode: 120, modifierMask: fn | ctrl, isEnabled: true)

    private func make(_ store: FakeSystemShortcutStore) -> (SystemShortcutManager, ConfigStore) {
        let config = ConfigStore(root: FileManager.default.temporaryDirectory.appending(path: "maio-ss-\(UUID().uuidString)"))
        return (SystemShortcutManager(store: store, config: config), config)
    }

    @Test func `detects globe conflicts exactly`() throws {
        let (manager, _) = make(FakeSystemShortcutStore([Self.dock, Self.quickNote]))
        #expect(try manager.conflicts(for: #require(KeyChord(string: "fn+a"))).map(\.id) == [210])
        #expect(try manager.conflicts(for: #require(KeyChord(string: "a"))).isEmpty)
        #expect(try manager.conflicts(for: #require(KeyChord(string: "fn+shift+a"))).isEmpty)
        #expect(try manager.conflicts(for: #require(KeyChord(string: "fn+b"))).isEmpty)
    }

    @Test func `implicit function keys ignore fn flag`() throws {
        let (manager, _) = make(FakeSystemShortcutStore([Self.space, Self.menuBar]))
        #expect(try manager.conflicts(for: #require(KeyChord(string: "ctrl+left"))).map(\.id) == [79])
        #expect(try manager.conflicts(for: #require(KeyChord(string: "fn+ctrl+left"))).map(\.id) == [79])
        #expect(try manager.conflicts(for: #require(KeyChord(string: "ctrl+f2"))).map(\.id) == [7])
        #expect(manager.globeShortcuts.isEmpty, "F 键和方向键不算 🌐 快捷键")
    }

    @Test func `media keys are not globe shortcuts`() {
        let brightness = RawSystemShortcut(id: 100, character: 65535, keyCode: 129, modifierMask: Self.fn, isEnabled: true)
        let (manager, _) = make(FakeSystemShortcutStore([brightness, Self.dock]))
        #expect(manager.globeShortcuts.map(\.id) == [210])
    }

    @Test func `names come from apple docs`() {
        let (manager, _) = make(FakeSystemShortcutStore([Self.dock, Self.quickNote, Self.menuBar]))
        let names = Dictionary(uniqueKeysWithValues: manager.shortcuts.map { ($0.id, $0.info.name) })
        #expect(names[210] == "显示或隐藏程序坞")
        #expect(names[190] == "新建快速备忘录")
        #expect(names[7] == "将焦点移到菜单栏")
        #expect(manager.shortcuts.first { $0.id == 210 }?.displayString == "🌐A")
    }

    @Test func `disable backs up and restore removes entry`() throws {
        let store = FakeSystemShortcutStore([Self.dock])
        let (manager, config) = make(store)
        manager.disable([210], reason: "fn+a → 活动监视器")
        #expect(try manager.conflicts(for: #require(KeyChord(string: "fn+a"))).isEmpty)
        #expect(store.preferences[210]?.objectValue?["enabled"] == .bool(false))
        let backup = try #require(manager.backup(for: 210))
        #expect(backup.originalEntry == nil)
        #expect(backup.originalEnabled)

        // 重启 MAIO 后备份仍在
        let reloaded = SystemShortcutManager(store: store, config: config)
        #expect(reloaded.backups.map(\.id) == [210])

        reloaded.restore(210)
        #expect(store.preferences[210] == nil, "原本没有条目，恢复后应删除条目以使用系统默认值")
        #expect(store.applied.last?.0 == 210)
        #expect(store.applied.last?.1 == true)
        #expect(reloaded.backups.isEmpty)
        #expect(try reloaded.conflicts(for: #require(KeyChord(string: "fn+a"))).map(\.id) == [210])
    }

    @Test func `restore keeps customized original entry`() {
        let store = FakeSystemShortcutStore([Self.quickNote])
        let custom: JSONValue = ["enabled": true, "value": ["type": "standard", "parameters": [113, 12, 8_388_608]]]
        store.preferences[190] = custom
        let (manager, _) = make(store)
        manager.disable([190], reason: nil)
        #expect(store.preferences[190]?.objectValue?["value"] == custom.objectValue?["value"], "只改 enabled，保留其他字段")
        manager.disable([190], reason: "第二次")
        #expect(manager.backups.count == 1, "重复禁用不能覆盖最早的备份")
        manager.restoreAll()
        #expect(store.preferences[190] == custom)
    }

    @Test func `plist bridge keeps integers and bools`() throws {
        let value: JSONValue = ["enabled": false, "parameters": [113, 12, 8_388_608]]
        let plist = try #require(PlistBridge.plist(from: value) as? [String: Any])
        #expect(plist["enabled"] as? Bool == false)
        #expect((plist["parameters"] as? [Any])?.first is Int)
        #expect(PlistBridge.json(from: plist) == value)
    }
}
