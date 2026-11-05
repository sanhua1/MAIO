/// Finder 的隐藏设置：写在 Finder 自己的配置里（ADR-0017），不是 MAIO 的设置。
/// 打开 = 写入 `enabledValue`；关闭 = 删除这个键，恢复系统默认。
enum PreferenceDomain: String, Codable, Sendable, Hashable {
    case finder
    /// 全局域（NSGlobalDomain），所有 App 共用
    case global
    /// .DS_Store 相关
    case desktopServices

    /// CFPreferences 的应用 ID；全局域由调用方换成 kCFPreferencesAnyApplication
    var applicationID: String? {
        switch self {
        case .finder: "com.apple.finder"
        case .global: nil
        case .desktopServices: "com.apple.desktopservices"
        }
    }
}

enum PreferenceValue: Codable, Sendable, Hashable {
    case bool(Bool)
    case string(String)

    /// 读到的原始值可能是 Bool、数字或 "YES"/"true" 字符串（`defaults write` 不带 -bool 时）
    static func normalized(_ raw: Any?) -> PreferenceValue? {
        switch raw {
        case let value as Bool: return .bool(value)
        case let value as Int: return .bool(value != 0)
        case let value as String:
            switch value.lowercased() {
            case "yes", "true", "1": return .bool(true)
            case "no", "false", "0": return .bool(false)
            default: return .string(value)
            }
        default: return nil
        }
    }
}

/// MAIO 第一次改某个 Finder 配置之前的原值（nil 表示原来没有这个键），用于一键还原
struct PreferenceBackup: Codable, Sendable, Equatable {
    var domain: PreferenceDomain
    var key: String
    var original: PreferenceValue?
}

struct FinderTweak: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let info: String
    let domain: PreferenceDomain
    let keys: [String]
    let enabledValue: PreferenceValue
    /// 改完要重新登录才完全生效（Finder 重启后新打开的窗口生效）
    var needsRelogin = false

    func isOn(_ current: PreferenceValue?) -> Bool {
        current == enabledValue
    }
}

/// 默认显示方式
enum FinderViewStyle: String, CaseIterable, Sendable {
    case system = ""
    case icon = "icnv"
    case list = "Nlsv"
    case column = "clmv"
    case gallery = "glyv"

    static let key = "FXPreferredViewStyle"

    var title: String {
        switch self {
        case .system: "系统默认"
        case .icon: "图标"
        case .list: "列表"
        case .column: "分栏"
        case .gallery: "画廊"
        }
    }
}

enum FinderTweaks {
    static let all: [FinderTweak] = display + behavior + files

    /// 显示
    static let display: [FinderTweak] = [
        FinderTweak(
            id: "showHidden", title: "显示隐藏文件", info: "显示以 . 开头的文件和系统隐藏的文件。Finder 里随时可以按 ⌘⇧. 临时切换。",
            domain: .finder, keys: ["AppleShowAllFiles"], enabledValue: .bool(true),
        ),
        FinderTweak(
            id: "showExtensions", title: "显示所有文件扩展名", info: "和 Finder 设置 › 高级 里的同名选项相同。",
            domain: .global, keys: ["AppleShowAllExtensions"], enabledValue: .bool(true),
        ),
        FinderTweak(
            id: "pathBar", title: "显示路径栏", info: "窗口底部显示当前位置的完整路径，可以点击跳转、拖放文件。",
            domain: .finder, keys: ["ShowPathbar"], enabledValue: .bool(true),
        ),
        FinderTweak(
            id: "statusBar", title: "显示状态栏", info: "窗口底部显示项目数和剩余空间。",
            domain: .finder, keys: ["ShowStatusBar"], enabledValue: .bool(true),
        ),
        FinderTweak(
            id: "posixTitle", title: "标题栏显示完整路径", info: "窗口标题显示 /Users/… 这样的完整路径，而不是只有文件夹名。",
            domain: .finder, keys: ["_FXShowPosixPathInTitle"], enabledValue: .bool(true),
        ),
        FinderTweak(
            id: "foldersFirst", title: "按名称排序时文件夹排在前面", info: "和 Windows 一样，文件夹总在文件前面。",
            domain: .finder, keys: ["_FXSortFoldersFirst"], enabledValue: .bool(true),
        ),
        FinderTweak(
            id: "foldersFirstDesktop", title: "桌面上文件夹也排在前面", info: "",
            domain: .finder, keys: ["_FXSortFoldersFirstOnDesktop"], enabledValue: .bool(true),
        ),
    ]

    /// 行为
    static let behavior: [FinderTweak] = [
        FinderTweak(
            id: "searchCurrentFolder", title: "搜索时默认只搜当前文件夹", info: "系统默认搜索整台 Mac。",
            domain: .finder, keys: ["FXDefaultSearchScope"], enabledValue: .string("SCcf"),
        ),
        FinderTweak(
            id: "noExtensionWarning", title: "修改扩展名时不再提示", info: "",
            domain: .finder, keys: ["FXEnableExtensionChangeWarning"], enabledValue: .bool(false),
        ),
        FinderTweak(
            id: "noTrashWarning", title: "清倒废纸篓时不再提示", info: "",
            domain: .finder, keys: ["WarnOnEmptyTrash"], enabledValue: .bool(false),
        ),
        FinderTweak(
            id: "quitMenu", title: "允许用 ⌘Q 退出 Finder", info: "Finder 菜单里会多出「退出 Finder」。退出后桌面图标也会消失，点程序坞里的 Finder 恢复。",
            domain: .finder, keys: ["QuitMenuItem"], enabledValue: .bool(true),
        ),
        FinderTweak(
            id: "noAnimations", title: "关闭 Finder 的动画", info: "打开窗口、显示简介等动画都去掉，感觉更快。",
            domain: .finder, keys: ["DisableAllAnimations"], enabledValue: .bool(true),
        ),
        FinderTweak(
            id: "expandedSavePanel", title: "保存对话框默认展开", info: "所有 App 的「存储」对话框默认显示完整的文件浏览器，而不是只有一个位置菜单。",
            domain: .global, keys: ["NSNavPanelExpandedStateForSaveMode", "NSNavPanelExpandedStateForSaveMode2"],
            enabledValue: .bool(true),
        ),
    ]

    /// 文件
    static let files: [FinderTweak] = [
        FinderTweak(
            id: "noNetworkDSStore", title: "不在网络磁盘上生成 .DS_Store", info: "访问共享文件夹（Windows 共享、NAS）时不留下 .DS_Store。",
            domain: .desktopServices, keys: ["DSDontWriteNetworkStores"], enabledValue: .bool(true), needsRelogin: true,
        ),
        FinderTweak(
            id: "noUSBDSStore", title: "不在 U 盘、移动硬盘上生成 .DS_Store", info: "插到 Windows 电脑上不会看到一堆 .DS_Store。",
            domain: .desktopServices, keys: ["DSDontWriteUSBStores"], enabledValue: .bool(true), needsRelogin: true,
        ),
    ]
}
