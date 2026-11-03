import AppKit

/// 遮罩把鼠标和键盘事件交给截图流程。坐标都已转换成全局坐标（左上角原点，pt）。
@MainActor
protocol OverlayEventHandler: AnyObject {
    func overlayMouseDown(at point: CGPoint, clickCount: Int, display: DisplayInfo)
    func overlayMouseDragged(to point: CGPoint)
    func overlayMouseUp(at point: CGPoint)
    func overlayMouseMoved(to point: CGPoint)
    func overlayRightMouseDown()
    func overlayScrollWheel(_ event: NSEvent)
    /// 返回 false 表示没有处理（交给系统，例如发出提示音）
    func overlayKeyDown(_ event: NSEvent) -> Bool
    func overlayFlagsChanged(_ flags: NSEvent.ModifierFlags)
}

/// 每个显示器一个遮罩窗口（ADR-0011）：无边框、屏保层级、所有桌面可见、可以成为 key window。
/// 预先创建并复用，不用时只是隐藏。
@MainActor
final class OverlayPanel: NSPanel {
    let overlayView: OverlayView

    init(display: DisplayInfo, frame: CGRect) {
        overlayView = OverlayView(display: display)
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        backgroundColor = .black
        isOpaque = true
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        overlayView.frame = CGRect(origin: .zero, size: frame.size)
        overlayView.autoresizingMask = [.width, .height]
        contentView = overlayView
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

/// 遮罩的内容视图：接收事件，内部是画布（图层合成）和工具栏。
@MainActor
final class OverlayView: NSView {
    private(set) var display: DisplayInfo
    weak var handler: (any OverlayEventHandler)?
    let canvas: OverlayCanvas

    init(display: DisplayInfo) {
        self.display = display
        canvas = OverlayCanvas(frame: .zero)
        super.init(frame: .zero)
        canvas.autoresizingMask = [.width, .height]
        addSubview(canvas)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func update(display: DisplayInfo) {
        self.display = display
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    /// 视图坐标（左下角原点）→ 全局坐标（左上角原点）
    func globalPoint(for event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return CGPoint(x: display.bounds.minX + local.x, y: display.bounds.minY + bounds.height - local.y)
    }

    /// 全局矩形 → 视图坐标
    func localRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - display.bounds.minX,
            y: bounds.height - (rect.maxY - display.bounds.minY),
            width: rect.width,
            height: rect.height,
        )
    }

    override func mouseDown(with event: NSEvent) {
        handler?.overlayMouseDown(at: globalPoint(for: event), clickCount: event.clickCount, display: display)
    }

    override func mouseDragged(with event: NSEvent) {
        handler?.overlayMouseDragged(to: globalPoint(for: event))
    }

    override func mouseUp(with event: NSEvent) {
        handler?.overlayMouseUp(at: globalPoint(for: event))
    }

    override func mouseMoved(with event: NSEvent) {
        handler?.overlayMouseMoved(to: globalPoint(for: event))
    }

    override func rightMouseDown(with _: NSEvent) {
        handler?.overlayRightMouseDown()
    }

    override func scrollWheel(with event: NSEvent) {
        handler?.overlayScrollWheel(event)
    }

    override func keyDown(with event: NSEvent) {
        if handler?.overlayKeyDown(event) != true {
            super.keyDown(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        handler?.overlayFlagsChanged(event.modifierFlags)
    }

    /// ⌘ 组合键会先走 performKeyEquivalent，这里统一交给 keyDown 的处理逻辑
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, window?.isKeyWindow == true else { return false }
        // 没处理的交给子视图（例如正在编辑的文字框处理 ⌘Z、⌘A）
        return handler?.overlayKeyDown(event) == true || super.performKeyEquivalent(with: event)
    }
}
