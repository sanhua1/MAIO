import Foundation
import MAIOKit
import Observation

/// MAIO 禁用某个系统快捷键前保存的原始状态。
public struct SystemShortcutBackup: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    /// 偏好设置中的原始条目；nil 表示原本使用系统默认值（恢复时删除条目即可）
    public let originalEntry: JSONValue?
    public let originalEnabled: Bool
    public let displayString: String
    public let name: String
    public let disabledAt: Date
    /// 为什么禁用，例如 "MAIO 绑定 fn A → 打开 App"
    public let reason: String?
}

/// 系统快捷键：冲突检测、带备份的禁用、一键恢复（见 ADR-0005）。
@MainActor
@Observable
public final class SystemShortcutManager {
    struct BackupFile: Codable {
        var schemaVersion = 1
        var backups: [SystemShortcutBackup] = []
    }

    static let path = "config/system-shortcuts-backup.json"

    public private(set) var shortcuts: [SystemShortcut] = []
    public private(set) var backups: [SystemShortcutBackup] = []
    @ObservationIgnored private var raws: [Int: RawSystemShortcut] = [:]
    @ObservationIgnored private let store: any SystemShortcutStore
    @ObservationIgnored private let config: ConfigStore

    init(store: any SystemShortcutStore, config: ConfigStore) {
        self.store = store
        self.config = config
        backups = config.load(BackupFile.self, from: Self.path, default: BackupFile()).backups
        refresh()
    }

    public var isAvailable: Bool {
        store.isAvailable
    }

    /// 重新读取系统状态（用户可能在系统设置里改过）。
    public func refresh() {
        let all = store.readAll()
        raws = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        shortcuts = all.map(\.shortcut)
    }

    /// 所有真正的 🌐 快捷键（不含 F 键、方向键这类自带 Fn 位的）。
    public var globeShortcuts: [SystemShortcut] {
        shortcuts.filter(\.isGlobeShortcut)
    }

    /// 与 MAIO 组合键冲突、且当前启用的系统快捷键。
    public func conflicts(for chord: KeyChord) -> [SystemShortcut] {
        shortcuts.filter { $0.isEnabled && $0.conflicts(with: chord) }
    }

    public func backup(for id: Int) -> SystemShortcutBackup? {
        backups.first { $0.id == id }
    }

    /// 禁用系统快捷键。第一次禁用时备份原始状态；重复禁用不会覆盖最早的备份。
    public func disable(_ ids: [Int], reason: String?) {
        for id in ids {
            guard let raw = raws[id] else { continue }
            let original = store.preferenceEntry(for: id)
            if backup(for: id) == nil {
                let shortcut = raw.shortcut
                backups.append(SystemShortcutBackup(
                    id: id, originalEntry: original, originalEnabled: raw.isEnabled,
                    displayString: shortcut.displayString, name: shortcut.info.name,
                    disabledAt: Date(), reason: reason,
                ))
            }
            store.apply(id: id, enabled: false, entry: Self.disabledEntry(original: original, raw: raw))
        }
        persist()
        refresh()
    }

    /// 恢复为 MAIO 修改之前的样子。
    public func restore(_ id: Int) {
        guard let backup = backup(for: id) else { return }
        store.apply(id: id, enabled: backup.originalEnabled, entry: backup.originalEntry)
        backups.removeAll { $0.id == id }
        persist()
        refresh()
    }

    public func restoreAll() {
        for backup in backups {
            store.apply(id: backup.id, enabled: backup.originalEnabled, entry: backup.originalEntry)
        }
        backups.removeAll()
        persist()
        refresh()
    }

    /// 保留原条目的其他字段，只把 enabled 改成 false。
    static func disabledEntry(original: JSONValue?, raw: RawSystemShortcut) -> JSONValue {
        guard case var .object(fields) = original, fields["value"] != nil else {
            return raw.preferenceEntry(enabled: false)
        }
        fields["enabled"] = .bool(false)
        return .object(fields)
    }

    private func persist() {
        config.save(BackupFile(backups: backups), to: Self.path)
    }
}
