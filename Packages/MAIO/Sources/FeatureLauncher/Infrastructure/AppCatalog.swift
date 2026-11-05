import Foundation

/// 应用目录：扫描几个固定的应用文件夹，得到可以搜索的应用列表。
/// 几百个应用，读 Info.plist 和本地化名称大约几十毫秒，在后台做。
enum AppCatalog {
    /// 按优先级排列：同一个 bundle ID 出现在多处时，保留靠前的那份
    static func directories(home: URL) -> [URL] {
        [
            URL(filePath: "/Applications", directoryHint: .isDirectory),
            home.appending(path: "Applications", directoryHint: .isDirectory),
            URL(filePath: "/System/Applications", directoryHint: .isDirectory),
            URL(filePath: "/System/Library/CoreServices/Applications", directoryHint: .isDirectory),
        ]
    }

    /// 不在上面几个文件夹里、但应该能搜到的系统应用
    static let extraApps = ["/System/Library/CoreServices/Finder.app"]

    /// 往下找几层（`/Applications/Utilities/xx.app`、`/Applications/某厂商/xx.app`）；不进 .app 里面
    static let maxDepth = 2

    static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [LauncherItem] {
        var urls: [URL] = []
        for directory in directories(home: home) {
            collect(in: directory, depth: 0, into: &urls)
        }
        urls += extraApps.map { URL(filePath: $0, directoryHint: .isDirectory) }
        var seen = Set<String>()
        var items: [LauncherItem] = []
        for url in urls {
            guard let item = item(for: url), seen.insert(item.id).inserted else { continue }
            items.append(item)
        }
        return items
    }

    private static func collect(in directory: URL, depth: Int, into urls: inout [URL]) {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        guard let children = try? manager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles],
        ) else { return }
        for child in children {
            if child.pathExtension == "app" {
                urls.append(child)
            } else if depth < maxDepth, (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                collect(in: child, depth: depth + 1, into: &urls)
            }
        }
    }

    /// 简体中文的名称，不管当前界面语言是什么都读出来（英文界面下也能用拼音搜到"微信"）。
    /// 第三方应用放在 `zh-Hans.lproj/InfoPlist.strings`（或 zh_CN）；系统应用放在 `InfoPlist.loctable`（各语言一起）。
    static let chineseLocalizations = ["zh-Hans", "zh_CN", "zh-Hans-CN", "zh"]

    static func chineseNames(of url: URL) -> [String] {
        let resources = url.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        var tables: [[String: Any]] = []
        for localization in chineseLocalizations {
            let file = resources.appending(path: "\(localization).lproj/InfoPlist.strings")
            if let table = NSDictionary(contentsOf: file) as? [String: Any] {
                tables.append(table)
            }
        }
        let loctable = resources.appending(path: "InfoPlist.loctable")
        if let all = NSDictionary(contentsOf: loctable) as? [String: Any] {
            tables += chineseLocalizations.compactMap { all[$0] as? [String: Any] }
        }
        return tables.flatMap { table in
            ["CFBundleDisplayName", "CFBundleName"].compactMap { table[$0] as? String }
        }
    }

    static func item(for url: URL) -> LauncherItem? {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary ?? [:]
        let localized = bundle?.localizedInfoDictionary ?? [:]
        let fileName = url.deletingPathExtension().lastPathComponent
        var displayName = FileManager.default.displayName(atPath: path)
        if displayName.hasSuffix(".app") {
            displayName = String(displayName.dropLast(4))
        }
        let names = [
            fileName,
            localized["CFBundleDisplayName"] as? String,
            localized["CFBundleName"] as? String,
            info["CFBundleDisplayName"] as? String,
            info["CFBundleName"] as? String,
        ].compactMap(\.self) + chineseNames(of: url)
        return .app(
            path: path, bundleID: bundle?.bundleIdentifier, title: displayName,
            subtitle: url.deletingLastPathComponent().path(percentEncoded: false), names: names,
        )
    }
}
