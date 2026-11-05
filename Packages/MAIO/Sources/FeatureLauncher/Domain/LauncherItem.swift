import Foundation

/// 结果列表里的一项
struct LauncherItem: Identifiable, Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case app(path: String, bundleID: String?)
        case file(path: String, isDirectory: Bool)
        case web(url: URL)
        /// MAIO 的命令（`symbol` 是所属功能的图标）
        case command(id: String, symbol: String)
        /// 系统设置的面板；`iconPath` / `iconType` 取图标用
        case settingsPane(id: String, iconPath: String, iconType: String?)
        case system(SystemAction)
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let keys: SearchKeys

    /// 结果右侧的类别文字
    var kindLabel: String {
        switch kind {
        case .app: "应用"
        case let .file(_, isDirectory): isDirectory ? "文件夹" : "文件"
        case .web: "网页"
        case .command: "MAIO"
        case .settingsPane: "系统设置"
        case .system: "系统操作"
        }
    }

    /// 用 SF Symbol 当图标的条目（MAIO 命令、系统操作）
    var symbolName: String? {
        switch kind {
        case let .command(_, symbol): symbol
        case let .system(action): action.symbol
        case .app, .file, .web, .settingsPane: nil
        }
    }

    /// 命令类（MAIO 命令、系统设置、系统操作）：执行前先把焦点还给原来的 App
    var isCommand: Bool {
        switch kind {
        case .command, .settingsPane, .system: true
        case .app, .file, .web: false
        }
    }

    /// 能"在 Finder 中显示"的路径
    var path: String? {
        switch kind {
        case let .app(path, _), let .file(path, _): path
        case .web, .command, .settingsPane, .system: nil
        }
    }

    static func app(path: String, bundleID: String?, title: String, subtitle: String, names: [String]) -> LauncherItem {
        LauncherItem(
            id: "app:" + (bundleID ?? path), kind: .app(path: path, bundleID: bundleID),
            title: title, subtitle: subtitle, keys: SearchKeys([title] + names),
        )
    }

    /// 文件或文件夹。副标题是所在文件夹（用户目录写成 ~）
    static func file(path: String, name: String, isDirectory: Bool, home: String) -> LauncherItem {
        let parent = (path as NSString).deletingLastPathComponent
        let shown = parent == home ? "~" : parent.hasPrefix(home + "/") ? "~" + parent.dropFirst(home.count) : parent
        return LauncherItem(
            id: "file:" + path, kind: .file(path: path, isDirectory: isDirectory), title: name, subtitle: shown, keys: .empty,
        )
    }

    /// MAIO 的命令；副标题是所属功能。"截图 历史"这样带功能名的写法也能搜到
    static func command(id: String, title: String, feature: String, symbol: String) -> LauncherItem {
        LauncherItem(
            id: "command:" + id, kind: .command(id: id, symbol: symbol), title: title, subtitle: feature,
            keys: SearchKeys([title, feature + " " + title]),
        )
    }

    static func settingsPane(_ pane: SettingsPane) -> LauncherItem {
        LauncherItem(
            id: "settings:" + pane.id, kind: .settingsPane(id: pane.id, iconPath: pane.path, iconType: pane.iconType),
            title: pane.name,
            subtitle: "打开系统设置的“\(pane.name)”", keys: SearchKeys([pane.name] + pane.otherNames),
        )
    }

    static func system(_ action: SystemAction) -> LauncherItem {
        LauncherItem(
            id: "system:" + action.rawValue, kind: .system(action), title: action.title, subtitle: action.summary,
            keys: SearchKeys([action.title] + action.keywords),
        )
    }

    static func web(_ engine: WebSearchEngine, text: String) -> LauncherItem? {
        guard let url = engine.url(for: text) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return LauncherItem(
            id: "web:" + engine.keyword, kind: .web(url: url),
            title: "用 \(engine.name) 搜索“\(trimmed)”", subtitle: url.host() ?? "", keys: .empty,
        )
    }
}

/// 一组结果（"全部"里按类别分组）
struct LauncherSection: Identifiable, Equatable {
    let title: String
    let items: [LauncherItem]

    var id: String {
        title
    }
}
