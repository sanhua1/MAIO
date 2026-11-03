import MAIOKit

/// 系统快捷键的说明知识库。
///
/// 依据：
/// - Apple「Mac 键盘快捷键」https://support.apple.com/zh-cn/102650
/// - Apple「Mac 窗口平铺图标和键盘快捷键」https://support.apple.com/zh-cn/guide/mac-help/mchl9674d0b0/mac
/// - 系统设置 KeyboardSettings.appex 中的名称（DefaultShortcutsTable、DefaultSpacesShortcuts.xml）
///
/// Apple 没有公开"内部编号 → 功能"的对照表，所以 🌐 快捷键按**组合键**匹配文档（编号在系统更新后可能变化），
/// 只有长期稳定、社区广泛记录的经典编号才按编号匹配。
enum SystemShortcutKnowledge {
    static let shortcutsDoc = "https://support.apple.com/zh-cn/102650"
    static let tilingDoc = "https://support.apple.com/zh-cn/guide/mac-help/mchl9674d0b0/mac"

    static func info(id: Int, keyCode: UInt16, modifiers: KeyModifiers) -> SystemShortcutInfo {
        let chord = KeyChord(keyCode: keyCode, modifiers: modifiers)
        let implicit = KeyCodes.implicitFunctionKeys.contains(keyCode)
        if !implicit, modifiers.contains(.function), let entry = globe[chord.string] {
            return SystemShortcutInfo(name: entry.name, source: entry.source, category: entry.category)
        }
        if let entry = byID[id] {
            return SystemShortcutInfo(name: entry.name, source: entry.source, category: entry.category)
        }
        if (118 ... 133).contains(id) {
            return SystemShortcutInfo(name: "切换到桌面 \(id - 117)", source: .systemSettings, category: "调度中心")
        }
        let category = modifiers.contains(.function) && !implicit ? "🌐 地球仪键" : "其他"
        return SystemShortcutInfo(name: "未公开说明的系统快捷键 #\(id)", source: .unknown, category: category)
    }

    private typealias Entry = (name: String, source: SystemShortcutInfo.Source, category: String)

    private static func doc(_ name: String, _ category: String = "🌐 地球仪键") -> Entry {
        (name, .appleDocs(shortcutsDoc), category)
    }

    private static func tiling(_ name: String) -> Entry {
        (name, .appleDocs(tilingDoc), "窗口平铺")
    }

    /// 按组合键匹配的 🌐 快捷键（Apple 文档）。
    private static let globe: [String: Entry] = [
        "fn+a": doc("显示或隐藏程序坞"),
        "fn+shift+a": doc("显示或隐藏 App（macOS 26 起；旧版为启动台）"),
        "fn+c": doc("显示或隐藏控制中心"),
        "fn+n": doc("显示或隐藏通知中心"),
        "fn+q": doc("新建快速备忘录"),
        "fn+h": doc("显示桌面"),
        "fn+d": doc("开始或停止听写"),
        "fn+e": doc("显示字符检视器（表情与符号）"),
        "fn+ctrl+f": tiling("填充：窗口铺满桌面"),
        "fn+ctrl+c": tiling("居中：窗口移到桌面中央"),
        "fn+ctrl+r": tiling("恢复上一个大小"),
    ]

    /// 按编号匹配的经典系统快捷键。
    private static let byID: [Int: Entry] = [
        7: doc("将焦点移到菜单栏", "键盘导航"),
        8: doc("将焦点移到程序坞", "键盘导航"),
        9: doc("将焦点移到活跃窗口或下一个窗口", "键盘导航"),
        10: doc("将焦点移到窗口工具栏", "键盘导航"),
        11: doc("将焦点移到浮动窗口", "键盘导航"),
        12: ("打开或关闭键盘导航", .systemSettings, "键盘导航"),
        13: doc("更改 Tab 键移动焦点的方式", "键盘导航"),
        57: doc("将焦点移到状态菜单", "键盘导航"),
        27: ("将焦点移到下一个窗口", .systemSettings, "键盘导航"),
        28: ("将屏幕快照存储为文件", .systemSettings, "截屏"),
        29: ("将屏幕快照拷贝到剪贴板", .systemSettings, "截屏"),
        30: ("将所选区域的快照存储为文件", .systemSettings, "截屏"),
        31: ("将所选区域的快照拷贝到剪贴板", .systemSettings, "截屏"),
        184: ("截屏和录制选项", .systemSettings, "截屏"),
        32: ("调度中心", .systemSettings, "调度中心"),
        33: ("应用程序窗口", .systemSettings, "调度中心"),
        36: doc("显示桌面", "调度中心"),
        79: ("向左移动一个桌面", .systemSettings, "调度中心"),
        81: ("向右移动一个桌面", .systemSettings, "调度中心"),
        52: ("打开/关闭程序坞隐藏", .systemSettings, "程序坞"),
        60: ("选择上一个输入法", .systemSettings, "输入法"),
        61: ("选择输入菜单中的下一个输入法", .systemSettings, "输入法"),
        64: ("显示“聚焦”搜索", .systemSettings, "聚焦"),
        65: ("显示“访达”搜索窗口", .systemSettings, "聚焦"),
        98: ("显示帮助菜单", .systemSettings, "App 快捷键"),
        // 窗口平铺（编号与组合键已在 macOS 26.5 上逐一对照 Apple 窗口平铺文档）
        240: tiling("平铺到左半部"), 241: tiling("平铺到右半部"),
        242: tiling("平铺到上半部"), 243: tiling("平铺到下半部"),
        248: tiling("左和右排列"), 249: tiling("右和左排列"),
        250: tiling("上和下排列"), 251: tiling("下和上排列"),
        252: tiling("左侧与四分排列"), 253: tiling("右侧与四分排列"),
        254: tiling("上方与四分排列"), 255: tiling("下方与四分排列"),
    ]
}
