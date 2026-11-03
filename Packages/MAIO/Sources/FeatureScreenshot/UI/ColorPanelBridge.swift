import AppKit

/// 自定义颜色：打开系统颜色面板（显示在截图遮罩上面），选好后回调。
@MainActor
final class ColorPanelBridge: NSObject {
    var onChange: (AnnotationColor) -> Void = { _ in }
    private var isOpen = false

    func open(current: AnnotationColor) {
        let panel = NSColorPanel.shared
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.showsAlpha = false
        // 拖动色盘时不连续回调，松手才回调一次（否则每一点变化都会进撤销记录）
        panel.isContinuous = false
        panel.color = TextRendering.nsColor(current)
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.orderFront(nil)
        isOpen = true
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.orderOut(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        guard let srgb = sender.color.usingColorSpace(.sRGB) else { return }
        onChange(AnnotationColor(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent))
    }
}
