/// 面板的网格布局（纯逻辑，可单测）。
///
/// 用户要求像 Windows 一样尽量排成矩形，方便用方向键上下左右移动：
/// 1–3 项排成一行；4 项及以上按接近正方形排列（4 → 2×2，5–6 → 3 列，7–9 → 3×3，10–16 → 4 列……）。
enum SwitcherLayout {
    static func columns(count: Int, maxColumns: Int) -> Int {
        guard count > 0 else { return 1 }
        let ideal = count <= 3 ? count : Int(Double(count).squareRoot().rounded(.up))
        return max(1, min(ideal, maxColumns))
    }

    /// 向下：同一列的下一行；已在最下面（或下一行这一列没有项）时回到第一行。
    static func below(_ index: Int, columns: Int, count: Int) -> Int {
        let next = index + columns
        return next < count ? next : index % columns
    }

    /// 向上：同一列的上一行；已在第一行时回到这一列的最后一项。
    static func above(_ index: Int, columns: Int, count: Int) -> Int {
        let previous = index - columns
        if previous >= 0 {
            return previous
        }
        let column = index % columns
        let lastRowStart = (count - 1) / columns * columns
        let candidate = lastRowStart + column
        return candidate < count ? candidate : candidate - columns
    }
}

/// 网格中的一格：位置 + 窗口本身（值）。
///
/// 界面必须直接使用这里的 `item`，不能再用序号去 `items[index]` 取值：
/// 窗口数变少时（例如刚 ⌘Q 关掉一个 App），SwiftUI 会先用旧序号刷新旧格子，越界直接崩溃（2026-11-02 实际发生 4 次）。
struct SwitcherCellSlot: Identifiable, Hashable {
    let index: Int
    let item: SwitcherItem

    var id: SwitcherItem.ID {
        item.id
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.index == rhs.index && lhs.item.id == rhs.item.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(item.id)
    }
}

struct SwitcherGridRow: Identifiable, Hashable {
    let id: Int
    let slots: [SwitcherCellSlot]
}

extension SwitcherLayout {
    static func rows(items: [SwitcherItem], columns: Int) -> [SwitcherGridRow] {
        let width = max(1, columns)
        let slots = items.enumerated().map { SwitcherCellSlot(index: $0.offset, item: $0.element) }
        return stride(from: 0, to: slots.count, by: width).map { start in
            SwitcherGridRow(id: start / width, slots: Array(slots[start ..< min(start + width, slots.count)]))
        }
    }
}
