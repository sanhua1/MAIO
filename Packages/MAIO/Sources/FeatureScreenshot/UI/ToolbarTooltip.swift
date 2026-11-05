import AppKit
import MAIOUI
import SwiftUI

/// 工具栏的悬停提示条（截图遮罩是自绘窗口，系统的 `.help` 提示不会出现）。
/// 显示在当前指针下方，靠近屏幕边缘时翻到上方或左侧；不接收鼠标事件。
@MainActor
final class ToolbarTooltip {
    private var panel: NSPanel?

    /// 显示提示。位置按当前指针计算，调用方负责在离开控件时隐藏
    func show(_ text: String) {
        let panel = makePanel()
        let view = NSHostingView(rootView: ToolbarTooltipView(text: text))
        let size = view.fittingSize
        view.frame = CGRect(origin: .zero, size: size)
        panel.contentView = view
        panel.setFrame(CGRect(origin: origin(for: size), size: size), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        if let panel {
            return panel
        }
        let panel = TooltipPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false,
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        // 遮罩在 screenSaver 层，提示必须再高一层才看得见
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.panel = panel
        return panel
    }

    /// 指针右下方；下面放不下放上面，右边放不下放左边
    private func origin(for size: CGSize) -> CGPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        var x = mouse.x + 12
        var y = mouse.y - size.height - 14
        if y < visible.minY + 4 {
            y = mouse.y + 14
        }
        if x + size.width > visible.maxX - 4 {
            x = mouse.x - size.width - 12
        }
        return CGPoint(
            x: min(max(visible.minX + 4, x), max(visible.minX + 4, visible.maxX - size.width - 4)),
            y: min(max(visible.minY + 4, y), max(visible.minY + 4, visible.maxY - size.height - 4)),
        )
    }
}

private struct ToolbarTooltipView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .panelGlass(cornerRadius: 7)
            .fixedSize()
    }
}

/// 提示条不能成为 key window，否则截图遮罩会失去焦点（文字输入框会中断）
private final class TooltipPanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}
