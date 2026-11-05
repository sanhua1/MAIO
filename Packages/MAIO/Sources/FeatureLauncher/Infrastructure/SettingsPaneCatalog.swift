import Foundation
import IOKit.ps

/// 系统设置的各个面板：读 /System/Library/ExtensionKit/Extensions 里的设置扩展（`com.apple.Settings.extension.ui`），
/// 名称取系统当前语言的本地化名称，所以系统升级增删面板时自动跟上。大约 250 个扩展，读 Info.plist 几十毫秒，在后台做。
enum SettingsPaneCatalog {
    static let directory = URL(filePath: "/System/Library/ExtensionKit/Extensions", directoryHint: .isDirectory)
    static let extensionPoint = "com.apple.Settings.extension.ui"
    /// 普通用户的系统设置里看不到的面板
    static let hidden: Set<String> = [
        "com.apple.FollowUpSettings.FollowUpSettingsExtension",
        "com.apple.ClassKit-Settings.extension",
        "com.apple.Classroom-Settings.extension",
        "com.apple.HeadphoneSettings",
    ]

    static func scan() -> [SettingsPane] {
        let manager = FileManager.default
        guard let bundles = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        let battery = hasBattery()
        var seen = Set<String>()
        return bundles.filter { $0.pathExtension == "appex" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { pane(at: $0, hasBattery: battery) }
            .filter { seen.insert($0.id).inserted }
    }

    private static func pane(at url: URL, hasBattery: Bool) -> SettingsPane? {
        let contents = url.appending(path: "Contents")
        guard let info = NSDictionary(contentsOf: contents.appending(path: "Info.plist")) as? [String: Any],
              let id = info["CFBundleIdentifier"] as? String, !hidden.contains(id),
              let attributes = info["EXAppExtensionAttributes"] as? [String: Any],
              attributes["EXExtensionPointIdentifier"] as? String == extensionPoint,
              let settings = attributes["SettingsExtensionAttributes"] as? [String: Any],
              settings["allowsXAppleSystemPreferencesURLScheme"] as? Bool == true
        else { return nil }
        let representation = (settings["representations"] as? [[String: Any]])?.first { item in
            matches(item["predicate"] as? String, hasBattery: hasBattery)
        }
        let names = LocalizedNames(
            resources: contents.appending(path: "Resources"),
            sidebarKey: representation?["sidebar-name"] as? String,
        )
        guard let name = names.preferred else { return nil }
        let english = names.name(in: "en") ?? plainName(info["CFBundleDisplayName"] as? String)
        // Wi‑Fi 的名称里是不换行连字符（U+2011），加一个普通写法，输入 wifi / wi-fi 都能搜到
        let others = [english, name.replacingOccurrences(of: "\u{2011}", with: "-")].compactMap(\.self).filter { $0 != name }
        return SettingsPane(
            id: id, name: name, otherNames: others, path: url.path(percentEncoded: false),
            iconType: representation?["sidebar-iconUTTypeIdentifier"] as? String,
        )
    }

    /// 只认电池这一种条件（"电池"和"节能"是同一个面板在有无电池时的两种样子）
    private static func matches(_ predicate: String?, hasBattery: Bool) -> Bool {
        guard let predicate else { return true }
        if predicate.contains("battery == YES") {
            return hasBattery
        }
        if predicate.contains("battery != YES") {
            return !hasBattery
        }
        return true
    }

    /// Info.plist 里的名字有时是工程名（"AccessibilitySettingsExtension"），这种不要
    private static func plainName(_ name: String?) -> String? {
        guard let name, !["Extension", "Settings", "Preference", "Ext"].contains(where: name.contains) else { return nil }
        return name
    }

    private static func hasBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return false }
        return list.contains { source in
            let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
            return description?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        }
    }
}

/// 扩展的本地化名称：InfoPlist.loctable 里的 CFBundleDisplayName，没有时用侧边栏名称的键去 Localizable.loctable 里查
private struct LocalizedNames {
    let infoPlist: [String: [String: Any]]
    let strings: [String: [String: Any]]
    let sidebarKey: String?

    init(resources: URL, sidebarKey: String?) {
        infoPlist = Self.table(resources.appending(path: "InfoPlist.loctable"))
        strings = sidebarKey == nil ? [:] : Self.table(resources.appending(path: "Localizable.loctable"))
        self.sidebarKey = sidebarKey
    }

    /// 系统当前语言的名称
    var preferred: String? {
        let languages = Bundle.preferredLocalizations(from: Array(infoPlist.keys), forPreferences: Locale.preferredLanguages)
        return languages.lazy.compactMap { name(in: $0) }.first ?? name(in: "en")
    }

    func name(in language: String) -> String? {
        let info = infoPlist[language]
        let found = info?["CFBundleDisplayName"] as? String ?? info?["CFBundleName"] as? String
            ?? sidebarKey.flatMap { strings[language]?[$0] as? String }
        guard let found, !found.isEmpty else { return nil }
        return found
    }

    private static func table(_ url: URL) -> [String: [String: Any]] {
        NSDictionary(contentsOf: url) as? [String: [String: Any]] ?? [:]
    }
}
