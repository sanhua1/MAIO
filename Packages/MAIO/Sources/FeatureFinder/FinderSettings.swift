import MAIOKit

/// 动作表里一行的设置
struct FinderShortcutSetting: Codable, Sendable, Equatable {
    var isEnabled = true
    /// nil 表示用默认快捷键
    var chord: KeyChord?
}

/// 设置项：字段只增不删；结构不兼容的修改要提升 schemaVersion 并实现 migrate。
/// Finder 自己的隐藏设置和原生快捷键不在这里，直接读写 Finder 的配置。
struct FinderSettings: FeatureSettings {
    static let defaultValue = FinderSettings()

    /// 键是 `FinderActionID.rawValue`；没有的动作用默认值
    var shortcuts: [String: FinderShortcutSetting] = [:]
    /// ⌥⌘N 新建的文件名（重名时自动加 2、3…）
    var newFileName = "新建文本文档.txt"
    /// 「在终端中打开」用的 App
    var terminalBundleID = "com.apple.Terminal"
    /// 在 Finder 里长按 ⌘ 显示快捷键速查面板
    var cheatSheetEnabled = true
    /// 按住多久显示（秒）
    var cheatSheetDelay = 0.8

    /// 右键菜单里关掉的项（`ContextMenuAction.rawValue`）
    var hiddenContextMenuItems: [String] = []

    static let cheatSheetDelayRange = 0.3 ... 2.0

    var contextMenuActions: Set<ContextMenuAction> {
        Set(ContextMenuAction.allCases.filter { !hiddenContextMenuItems.contains($0.rawValue) })
    }

    func setting(for action: FinderActionID) -> FinderShortcutSetting {
        shortcuts[action.rawValue] ?? FinderShortcutSetting()
    }

    /// 生效的快捷键：关掉或没有快捷键时为 nil
    func chord(for action: FinderActionID) -> KeyChord? {
        let setting = setting(for: action)
        guard setting.isEnabled else { return nil }
        return setting.chord ?? action.info.defaultChord
    }

    mutating func update(_ action: FinderActionID, _ change: (inout FinderShortcutSetting) -> Void) {
        var value = setting(for: action)
        change(&value)
        shortcuts[action.rawValue] = value == FinderShortcutSetting() ? nil : value
    }

    /// 合成过滤器配置。`menu` 是 Finder 菜单的当前快照，`overrides` 是 MAIO 刚写入、Finder 还没重启生效的原生快捷键
    func keyConfig(menu: [FinderMenuItem], overrides: [[String]: KeyChord] = [:]) -> FinderKeyConfig {
        var config = FinderKeyConfig(cheatSheet: cheatSheetEnabled)
        for action in FinderActionID.allCases {
            guard let chord = chord(for: action) else { continue }
            let trigger = FinderKeymap.normalized(chord)
            // 同一个键设给了两个动作：只认先出现的（设置页会标红）
            if config.triggers[trigger] == nil {
                config.triggers[trigger] = action
            }
            if let target = Self.resolve(action.info.target, menu: menu, overrides: overrides) {
                config.targets[action] = target
            }
        }
        if let copy = Self.resolve(FinderActions.copy, menu: menu, overrides: overrides) {
            config.copyChord = copy
        }
        return config
    }

    static func resolve(_ target: FinderActionTarget, menu: [FinderMenuItem], overrides: [[String]: KeyChord]) -> KeyChord? {
        switch target {
        case .main: return nil
        case let .key(chord): return chord
        case let .menu(path, fallback):
            if let pending = path.candidates.lazy.compactMap({ overrides[$0] }).first {
                return pending
            }
            return MenuShortcuts.find(path, in: menu)?.chord ?? fallback
        }
    }
}
