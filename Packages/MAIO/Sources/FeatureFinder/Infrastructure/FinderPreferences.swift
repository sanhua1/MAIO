import AppKit

/// 读写 Finder 自己的配置（ADR-0017）。不是 MAIO 的设置，所以不经过 SettingsService。
/// 写入后 Finder 要重启才生效（`restartFinder()`）。
@MainActor
enum FinderPreferences {
    static func value(_ tweak: FinderTweak) -> PreferenceValue? {
        guard let key = tweak.keys.first else { return nil }
        return value(key, in: tweak.domain)
    }

    static func value(_ key: String, in domain: PreferenceDomain) -> PreferenceValue? {
        PreferenceValue.normalized(CFPreferencesCopyAppValue(key as CFString, applicationID(domain)))
    }

    /// 打开写入 `enabledValue`，关闭删除这个键（恢复系统默认）
    static func set(_ tweak: FinderTweak, on: Bool) {
        for key in tweak.keys {
            write(key, value: on ? tweak.enabledValue : nil, in: tweak.domain)
        }
    }

    static func write(_ key: String, value: PreferenceValue?, in domain: PreferenceDomain) {
        let object: CFPropertyList? = switch value {
        case let .bool(flag): flag ? kCFBooleanTrue : kCFBooleanFalse
        case let .string(text): text as CFString
        case nil: nil
        }
        let app = applicationID(domain)
        CFPreferencesSetAppValue(key as CFString, object, app)
        CFPreferencesAppSynchronize(app)
    }

    /// Finder 配置里的任意值（例如 NSUserKeyEquivalents 字典）
    static func object(key: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, applicationID(.finder))
    }

    static func writeObject(_ object: CFPropertyList?, key: String) {
        let app = applicationID(.finder)
        CFPreferencesSetAppValue(key as CFString, object, app)
        CFPreferencesAppSynchronize(app)
    }

    /// 重启 Finder：退出后系统会自动重新打开它，窗口会恢复
    static func restartFinder() {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/killall")
        process.arguments = ["Finder"]
        try? process.run()
    }

    private static func applicationID(_ domain: PreferenceDomain) -> CFString {
        domain.applicationID.map { $0 as CFString } ?? kCFPreferencesAnyApplication
    }
}
