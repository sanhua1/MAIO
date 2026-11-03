import AppKit

/// 菜单栏图标：App 图标"彩虹叠片"的单色版——后面一张半透明卡片，前面一张卡片的轮廓，里面一个 ⌘。
/// 模板图（`isTemplate`），颜色跟随菜单栏深浅色；用代码画，任意缩放都清晰。
/// 坐标沿用设计稿：72 × 72 的画布，原点在中心，y 轴向上。
enum MenuBarIcon {
    static let size = NSSize(width: 18, height: 18)

    static func make() -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            draw(in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "MAIO"
        return image
    }

    private static func draw(in rect: NSRect) {
        guard let context = NSGraphicsContext.current else { return }
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX, yBy: rect.midY)
        transform.scale(by: rect.width / 72)
        transform.concat()

        // 后面的卡片：向右上错开，半透明（和 App 图标里错开叠放的彩色卡片一致）
        let back = NSBezierPath(roundedRect: NSRect(x: -17, y: -17, width: 44, height: 44), xRadius: 11, yRadius: 11)
        NSColor.black.withAlphaComponent(0.45).setFill()
        back.fill()

        // 前面的卡片：先挖空它盖住的部分，再描边
        let front = NSBezierPath(roundedRect: NSRect(x: -27, y: -27, width: 44, height: 44), xRadius: 11, yRadius: 11)
        context.compositingOperation = .clear
        front.fill()
        context.compositingOperation = .sourceOver
        NSColor.black.setStroke()
        front.lineWidth = 4.5
        front.stroke()

        let command = commandPath(center: NSPoint(x: -5, y: -5), half: 5.5, radius: 5.5)
        command.lineWidth = 4.2
        command.stroke()
    }

    /// ⌘：中间方框（边长 2·half），四条边各延长 radius，接一个 3/4 圆
    static func commandPath(center: NSPoint, half a: CGFloat, radius r: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.appendRect(NSRect(x: center.x - a, y: center.y - a, width: 2 * a, height: 2 * a))
        for (sx, sy) in [(1.0, 1.0), (-1.0, 1.0), (-1.0, -1.0), (1.0, -1.0)] {
            let corner = NSPoint(x: center.x + sx * a, y: center.y + sy * a)
            let circle = NSPoint(x: center.x + sx * (a + r), y: center.y + sy * (a + r))
            // 起点在竖边的延长线上（圆心的水平方向），终点在横边的延长线上（圆心的竖直方向）
            let start: CGFloat = sx > 0 ? 180 : 0
            let end: CGFloat = sy > 0 ? 270 : 90
            // 走远的那一侧（270°），不经过方框的角
            let counterClockwiseSweep = (end - start + 360).truncatingRemainder(dividingBy: 360)
            path.move(to: corner)
            path.line(to: NSPoint(x: corner.x, y: circle.y))
            path.appendArc(
                withCenter: circle,
                radius: r,
                startAngle: start,
                endAngle: end,
                clockwise: counterClockwiseSweep == 90,
            )
            path.line(to: corner)
        }
        return path
    }
}
