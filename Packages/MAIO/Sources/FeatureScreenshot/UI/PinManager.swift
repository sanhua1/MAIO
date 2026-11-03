import AppKit

/// 管理所有贴图窗口。
@MainActor
final class PinManager {
    private(set) var pins: [PinWindow] = []
    var onAction: (PinWindow, PinAction) -> Void = { _, _ in }
    var controls: () -> PinControls = { PinControls() }

    /// 贴一张图。contentRect 是贴图内容的全局矩形（左上角原点，pt）
    @discardableResult
    func pin(image: CGImage, scale: CGFloat, contentRect: CGRect, recordID: String?, showsShadow: Bool) -> PinWindow {
        let pin = PinWindow(
            image: image, scale: scale, contentRect: contentRect, recordID: recordID, showsShadow: showsShadow,
        )
        pin.onAction = { [weak self] pin, action in self?.onAction(pin, action) }
        pin.controls = { [weak self] in self?.controls() ?? PinControls() }
        pins.append(pin)
        pin.orderFrontRegardless()
        return pin
    }

    func close(_ pin: PinWindow) {
        pin.orderOut(nil)
        pin.close()
        pins.removeAll { $0 === pin }
    }

    func closeAll() {
        for pin in pins {
            pin.orderOut(nil)
            pin.close()
        }
        pins.removeAll()
    }

    /// 没有原始位置时（贴剪贴板、从历史贴）：放在鼠标所在屏幕的中间，太大时缩小到屏幕的 80%
    static func centeredRect(for size: CGSize) -> (rect: CGRect, zoom: CGFloat) {
        let mouse = CaptureSession.globalMouseLocation()
        let displays = DisplayInfo.all()
        let bounds = (displays.first { $0.bounds.contains(mouse) } ?? displays.first)?.bounds
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let zoom = min(1, bounds.width * 0.8 / max(size.width, 1), bounds.height * 0.8 / max(size.height, 1))
        let fitted = CGSize(width: (size.width * zoom).rounded(), height: (size.height * zoom).rounded())
        let origin = CGPoint(x: (bounds.midX - fitted.width / 2).rounded(), y: (bounds.midY - fitted.height / 2).rounded())
        return (CGRect(origin: origin, size: fitted), zoom)
    }
}
