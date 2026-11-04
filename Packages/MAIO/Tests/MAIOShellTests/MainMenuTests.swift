import AppKit
@testable import MAIOShell
import MAIOUI
import SwiftUI
import Testing

@MainActor
struct MainMenuTests {
    private let menu = MainMenu {}.make()

    /// 菜单里所有带快捷键的项：快捷键（修饰键 + 字符）→ 动作
    private var shortcuts: [String: Selector] {
        var result: [String: Selector] = [:]
        for holder in menu.items {
            for item in holder.submenu?.items ?? [] where !item.keyEquivalent.isEmpty {
                if let action = item.action {
                    result[Self.name(item.keyEquivalentModifierMask, item.keyEquivalent)] = action
                }
            }
        }
        return result
    }

    private static func name(_ modifiers: NSEvent.ModifierFlags, _ key: String) -> String {
        var text = ""
        if modifiers.contains(.option) {
            text += "⌥"
        }
        if modifiers.contains(.shift) {
            text += "⇧"
        }
        if modifiers.contains(.command) {
            text += "⌘"
        }
        return text + key
    }

    @Test func `standard editing shortcuts go to the focused text field`() {
        #expect(shortcuts["⌘c"] == #selector(NSText.copy(_:)))
        #expect(shortcuts["⌘v"] == #selector(NSText.paste(_:)))
        #expect(shortcuts["⌘x"] == #selector(NSText.cut(_:)))
        #expect(shortcuts["⌘a"] == #selector(NSText.selectAll(_:)))
        #expect(shortcuts["⌘z"] == NSSelectorFromString("undo:"))
        #expect(shortcuts["⇧⌘z"] == NSSelectorFromString("redo:"))
        #expect(shortcuts["⌥⇧⌘v"] == #selector(NSTextView.pasteAsPlainText(_:)))
    }

    @Test func `command W closes and command M minimizes the current window`() {
        #expect(shortcuts["⌘w"] == #selector(NSWindow.performClose(_:)))
        #expect(shortcuts["⌘m"] == #selector(NSWindow.performMiniaturize(_:)))
    }

    @Test func `command Q and command H are not bound`() {
        // 面板盖在别的 App 上时，习惯性按 ⌘Q 不能把 MAIO 退出
        #expect(shortcuts["⌘q"] == nil)
        #expect(shortcuts["⌘h"] == nil)
    }

    @Test func `command comma opens settings`() throws {
        var opened = 0
        let mainMenu = MainMenu { opened += 1 }
        let settings = try #require(mainMenu.make().items.first?.submenu?.items.first { $0.keyEquivalent == "," })
        #expect(settings.target === mainMenu)
        mainMenu.openSettings()
        #expect(opened == 1)
    }

    @Test func `borderless panel closes through its own handler`() {
        let panel = FloatingPanel(rootView: Text("x"), acceptsKeyboard: true)
        let close = NSMenuItem(title: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        // 没有关闭按钮：默认不可用，⌘W 不会发给它
        #expect(!panel.validateMenuItem(close))
        var closed = 0
        panel.onCloseCommand = { closed += 1 }
        #expect(panel.validateMenuItem(close))
        panel.performClose(nil)
        #expect(closed == 1)
    }
}
