import Foundation
import MAIOKit

/// 一键还原：MAIO 第一次改 Finder 的某个配置前记下原值，还原时全部写回。
/// 存在 `data/finder/backups.json`，不放进 FinderSettings（设置页各自持有设置副本，保存时会互相覆盖）。
@MainActor
struct FinderBackups {
    struct File: Codable, Equatable {
        /// 隐藏设置的原值，键是 "域|键"
        var preferences: [String: PreferenceBackup] = [:]
        /// 原生快捷键的原值：NSUserKeyEquivalents 的键 → 原来的值（空字符串表示原来没有）
        var menuShortcuts: [String: String] = [:]
    }

    let url: URL

    init?(storage: any StorageService) {
        guard let directory = try? storage.dataDirectory() else { return nil }
        url = directory.appending(path: "backups.json")
    }

    func load() -> File {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(File.self, from: $0) } ?? File()
    }

    private func save(_ file: File) {
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: url, options: .atomic)
    }

    var hasBackups: Bool {
        load() != File()
    }

    func rememberPreference(_ key: String, in domain: PreferenceDomain) {
        var file = load()
        let id = "\(domain.rawValue)|\(key)"
        guard file.preferences[id] == nil else { return }
        file.preferences[id] = PreferenceBackup(domain: domain, key: key, original: FinderPreferences.value(key, in: domain))
        save(file)
    }

    func rememberTweak(_ tweak: FinderTweak) {
        tweak.keys.forEach { rememberPreference($0, in: tweak.domain) }
    }

    /// 改原生快捷键之前调用：记下完整路径和只有标题两种写法的原值
    func rememberMenuShortcut(_ path: [String]) {
        var file = load()
        let raw = FinderPreferences.object(key: FinderMenuStore.key) as? [String: String] ?? [:]
        for key in [MenuShortcuts.preferenceKey(path), path.last ?? ""] where file.menuShortcuts[key] == nil {
            file.menuShortcuts[key] = raw[key] ?? ""
        }
        save(file)
    }

    /// 把 MAIO 改过的隐藏设置和原生快捷键全部写回原值，然后清空备份。之后要重启 Finder
    func restoreAll() {
        let file = load()
        for backup in file.preferences.values {
            FinderPreferences.write(backup.key, value: backup.original, in: backup.domain)
        }
        if !file.menuShortcuts.isEmpty {
            var raw = FinderPreferences.object(key: FinderMenuStore.key) as? [String: String] ?? [:]
            for (key, original) in file.menuShortcuts {
                raw[key] = original.isEmpty ? nil : original
            }
            FinderPreferences.writeObject(raw.isEmpty ? nil : raw as CFDictionary, key: FinderMenuStore.key)
        }
        save(File())
    }
}
