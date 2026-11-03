import CoreGraphics

/// 剪贴板面板放在哪（Cocoa 坐标，原点在左下）。纯函数，可单测。
enum PopupPlacement {
    /// 面板和光标所在行之间留的空隙
    static let gap: CGFloat = 6
    /// 面板内容的左内边距：左移这么多，列表文字正好和光标对齐
    static let contentInset: CGFloat = 12

    /// 放在 anchor（光标所在的那一行、或鼠标处）的正下方；下方放不下时放到上方，不挡住这一行。
    /// 返回面板左上角。
    static func topLeft(around anchor: CGRect, size: CGSize, in visible: CGRect) -> CGPoint {
        var y = anchor.minY - gap
        if y - size.height < visible.minY {
            y = anchor.maxY + gap + size.height
        }
        let x = min(max(anchor.minX - contentInset, visible.minX + 4), visible.maxX - size.width - 4)
        y = min(max(y, visible.minY + size.height), visible.maxY)
        return CGPoint(x: x, y: y)
    }

    /// 屏幕正中间
    static func centered(size: CGSize, in visible: CGRect) -> CGPoint {
        CGPoint(x: visible.midX - size.width / 2, y: visible.midY + size.height / 2)
    }
}
