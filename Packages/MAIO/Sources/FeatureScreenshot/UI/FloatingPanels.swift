import AppKit

/// 长截图、录屏时浮在屏幕上的面板（边框、控制条）：不抢焦点、所有桌面可见。
/// 它们都是 MAIO 的窗口，截图和录屏时会被排除，不会出现在结果里。
@MainActor
enum FloatingPanels {
    static func make(frame: CGRect) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }

    /// 选区外 2 pt 的虚线边框面板（不挡鼠标）
    static func border(around rect: CGRect, color: NSColor = .controlAccentColor) -> NSPanel {
        let panel = make(frame: appKitRect(rect).insetBy(dx: -2, dy: -2))
        panel.ignoresMouseEvents = true
        let view = DashedBorderView(frame: CGRect(origin: .zero, size: panel.frame.size))
        view.color = color
        panel.contentView = view
        return panel
    }

    /// 全局坐标（左上角原点）→ AppKit 屏幕坐标（左下角原点）
    static func appKitRect(_ rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func visibleFrame(containing frame: CGRect) -> CGRect {
        (NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main)?.visibleFrame ?? frame
    }
}

/// 1 px 虚线边框
final class DashedBorderView: NSView {
    var color = NSColor.controlAccentColor {
        didSet { needsDisplay = true }
    }

    override func draw(_: NSRect) {
        color.setStroke()
        let path = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1
        path.setLineDash([6, 4], count: 2, phase: 0)
        path.stroke()
    }
}
