import AppKit

/// App 的主菜单。MAIO 平时不显示菜单栏（只有菜单栏图标），但 ⌘C、⌘V、⌘A、⌘Z、⌘W 这些标准快捷键要靠主菜单分发：
/// 系统把它们当作菜单项的快捷键，发给当前的输入框或窗口。没有主菜单时，所有窗口里的这些键都没有反应。
/// 打开设置窗口时（出现程序坞图标）这套菜单也会显示在屏幕顶部。
///
/// 各窗口自己处理的 ⌘ 组合键不受影响，因为它们都在菜单之前拿到按键：
/// - 贴图、截图遮罩在 `performKeyEquivalent` 里先处理（遮罩只在编辑文字标注时把按键让给文字框）；
/// - 剪贴板面板的按键监听在菜单之前；
/// - 截图历史的 ⌘C：没有输入框时，菜单的「拷贝」不可用，按键照常交给它。
///
/// 不绑定 ⌘Q、⌘H：MAIO 的面板经常盖在别的 App 上，习惯性按 ⌘Q 想退出下面的 App，会误退出 MAIO。
@MainActor
final class MainMenu: NSObject {
    private let openSettingsAction: () -> Void

    init(openSettings: @escaping () -> Void) {
        openSettingsAction = openSettings
    }

    func install() {
        NSApp.mainMenu = make()
    }

    func make() -> NSMenu {
        let menu = NSMenu()
        // 第一个子菜单是"应用程序菜单"，标题由系统显示为 App 名
        menu.addItem(Self.submenu("MAIO", appItems()))
        menu.addItem(Self.submenu("编辑", Self.editItems()))
        menu.addItem(Self.submenu("窗口", Self.windowItems()))
        return menu
    }

    private func appItems() -> [NSMenuItem] {
        let settings = Self.item("设置…", #selector(openSettings), ",")
        settings.target = self
        return [
            Self.item("关于 MAIO", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            settings,
            .separator(),
            Self.item("退出 MAIO", #selector(NSApplication.terminate(_:))),
        ]
    }

    /// 动作发给当前的第一响应者（输入框）；没有能处理的就不可用，按键继续交给窗口
    static func editItems() -> [NSMenuItem] {
        [
            item("撤销", #selector(UndoActions.undo(_:)), "z"),
            item("重做", #selector(UndoActions.redo(_:)), "z", [.command, .shift]),
            .separator(),
            item("剪切", #selector(NSText.cut(_:)), "x"),
            item("拷贝", #selector(NSText.copy(_:)), "c"),
            item("粘贴", #selector(NSText.paste(_:)), "v"),
            item("粘贴并匹配样式", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift]),
            item("删除", #selector(NSText.delete(_:))),
            item("全选", #selector(NSText.selectAll(_:)), "a"),
        ]
    }

    /// 标准窗口用系统的关闭 / 最小化；无边框面板的 ⌘W 见 `FloatingPanel.onCloseCommand`
    static func windowItems() -> [NSMenuItem] {
        [
            item("最小化", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("关闭", #selector(NSWindow.performClose(_:)), "w"),
        ]
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = menu
        return holder
    }

    private static func item(
        _ title: String,
        _ action: Selector,
        _ key: String = "",
        _ modifiers: NSEvent.ModifierFlags = .command,
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    @objc func openSettings() {
        openSettingsAction()
    }
}

/// 撤销 / 重做由输入框和窗口通过响应链实现，没有公开的 Swift 声明，借一个 @objc 协议拿到选择器
@objc private protocol UndoActions {
    func undo(_ sender: Any?)
    func redo(_ sender: Any?)
}
