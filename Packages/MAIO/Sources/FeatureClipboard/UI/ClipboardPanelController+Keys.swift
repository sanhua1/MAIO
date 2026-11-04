import AppKit
import MAIOKit

/// 面板的按键：不在搜索时由这里处理（搜索框没有焦点），搜索时交给搜索框（ClipboardPanelView.handleKey）。
extension ClipboardPanelController {
    private enum Key {
        static let returnKey: UInt16 = 36
        static let enter: UInt16 = 76
        static let escape: UInt16 = 53
        static let space: UInt16 = 49
        static let up: UInt16 = 126
        static let down: UInt16 = 125
        static let f: UInt16 = 3
    }

    /// 返回 true 表示按键已处理（不再往下传）
    func intercept(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == KeyCodes.delete, modifiers == .command {
            model.deleteSelected()
            return true
        }
        guard model.isSearching else {
            return handleBrowsingKey(event, modifiers: modifiers)
        }
        model.keyIsComposing = Self.isComposing
        return false
    }

    /// 搜索框里有输入法正在组字的内容（拼音还没上屏）
    private static var isComposing: Bool {
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true
    }

    private func handleBrowsingKey(_ event: NSEvent, modifiers: NSEvent.ModifierFlags) -> Bool {
        let command = modifiers.contains(.command)
        switch event.keyCode {
        case Key.up: model.move(by: -1)
        case Key.down: model.move(by: 1)
        case Key.returnKey, Key.enter: model.pasteSelected(plainText: modifiers.contains(.shift))
        case Key.escape: escape()
        case Key.space: model.togglePreview()
        case KeyCodes.delete: model.deleteSelected()
        case Key.f where command: model.startSearch()
        default:
            guard command else { return true }
            return commandShortcut(event)
        }
        return true
    }

    /// ⌘1–9 快速粘贴、⌘P 固定；其他 ⌘ 组合交给主菜单（例如 ⌘W 关闭面板）
    private func commandShortcut(_ event: NSEvent) -> Bool {
        guard let character = event.charactersIgnoringModifiers?.first else { return false }
        if let digit = character.wholeNumberValue {
            model.pasteQuick(slot: digit)
            return true
        }
        if character == "p" {
            model.togglePinSelected()
            return true
        }
        return false
    }

    /// Esc：先关预览，再清空搜索结果，最后关闭面板
    private func escape() {
        if model.preview != nil {
            model.togglePreview()
        } else if !model.query.isEmpty {
            model.endSearch(clear: true)
        } else {
            model.onClose?()
        }
    }
}
