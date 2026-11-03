import MAIOKit

/// 一次切换会话的状态机（纯逻辑，可单测）。
///
/// 交互约定（与 Windows Alt+Tab、alt-tab-macos 一致）：
/// - 按住修饰键期间：主键 / Tab / → 下一项，⇧+主键 / ⇧Tab / ← 上一项，↑ ↓ 在网格中上下移动
/// - 松开触发时按住的修饰键：切换到选中项
/// - Esc 取消；Return / 空格 立即切换
/// - W 关闭窗口，M 最小化，H 隐藏 App，Q 退出 App（作用于选中项，会话继续）
struct SwitcherSession {
    enum Action: Equatable {
        case none
        case confirm
        case cancel
        case closeWindow(SwitcherItem)
        case minimizeWindow(SwitcherItem)
        case hideApp(SwitcherItem)
        case quitApp(SwitcherItem)
    }

    private(set) var items: [SwitcherItem]
    private(set) var selectedIndex: Int
    /// 触发组合键中的修饰键：全部松开（任一松开）即确认
    let holdModifiers: KeyModifiers
    let triggerKeyCode: UInt16
    /// 网格列数（由界面根据屏幕宽度计算），用于方向键上下移动
    var columns = 1

    /// reverse：由 ⇧ 版本的快捷键触发，从最后一项开始
    init(items: [SwitcherItem], trigger: KeyChord, reverse: Bool) {
        self.items = items
        holdModifiers = trigger.modifiers.subtracting(.shift)
        triggerKeyCode = trigger.keyCode
        if items.count < 2 {
            selectedIndex = 0
        } else {
            selectedIndex = reverse ? items.count - 1 : 1
        }
    }

    var selected: SwitcherItem? {
        items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }

    mutating func select(_ index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
    }

    /// 修饰键已经全部松开（会话开始前用户就松手了）时，直接确认，实现"快速按一下切回上一个窗口"。
    func isReleased(currentModifiers: KeyModifiers) -> Bool {
        !holdModifiers.isEmpty && !currentModifiers.isSuperset(of: holdModifiers)
    }

    mutating func handle(_ event: KeyEvent) -> Action {
        switch event.kind {
        case .flagsChanged:
            return isReleased(currentModifiers: event.modifiers) ? .confirm : .none
        case .up:
            return .none
        case .down:
            return handleKeyDown(event)
        }
    }

    private mutating func handleKeyDown(_ event: KeyEvent) -> Action {
        let backwards = event.modifiers.contains(.shift)
        switch event.keyCode {
        case triggerKeyCode, KeyCodes.tab:
            move(backwards ? -1 : 1)
        case Keys.right:
            move(1)
        case Keys.left:
            move(-1)
        case Keys.down:
            selectedIndex = SwitcherLayout.below(selectedIndex, columns: max(1, columns), count: items.count)
        case Keys.up:
            selectedIndex = SwitcherLayout.above(selectedIndex, columns: max(1, columns), count: items.count)
        case KeyCodes.escape:
            return .cancel
        case Keys.returnKey, Keys.space:
            return .confirm
        case Keys.w:
            return selected.map(Action.closeWindow) ?? .none
        case Keys.m:
            return selected.map(Action.minimizeWindow) ?? .none
        case Keys.h:
            return selected.map(Action.hideApp) ?? .none
        case Keys.q:
            return selected.map(Action.quitApp) ?? .none
        default:
            break
        }
        return .none
    }

    /// 窗口被关闭 / App 退出后，从列表中移除，选中项停在原位置。
    mutating func remove(where predicate: (SwitcherItem) -> Bool) {
        items.removeAll(where: predicate)
        selectedIndex = min(selectedIndex, max(items.count - 1, 0))
    }

    private mutating func move(_ offset: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex + offset + items.count) % items.count
    }

    private enum Keys {
        static let returnKey: UInt16 = 36
        static let space: UInt16 = 49
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
        static let w: UInt16 = 13
        static let m: UInt16 = 46
        static let h: UInt16 = 4
        static let q: UInt16 = 12
    }
}
