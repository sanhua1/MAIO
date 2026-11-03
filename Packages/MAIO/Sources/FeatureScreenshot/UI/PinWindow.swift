import AppKit

/// 贴图窗口的操作（由 PinManager 处理）
enum PinAction {
    case copy
    case save
    case edit
    case ocr
    case translate
    case close
    case closeAll
}

/// 一张钉在屏幕上的贴图（spec 3.3、4.4）。
/// 不抢焦点的面板，层级在 Dock 和菜单栏之上、弹出菜单之下；所有桌面可见，全屏 App 上方也能显示。
@MainActor
final class PinWindow: NSPanel {
    let id = UUID()
    /// 对应的历史记录（ADR-0012：每张贴图对应一条历史记录）
    var recordID: String?
    private(set) var image: CGImage
    /// 每 pt 的像素数
    private(set) var scale: CGFloat
    private(set) var state: PinState
    private let pinView: PinView
    var onAction: (PinWindow, PinAction) -> Void = { _, _ in }
    /// 缩放、透明度用哪个修饰键（读设置）
    var controls: () -> PinControls = { PinControls() }

    /// contentRect：贴图内容（不含阴影外边距）的全局矩形（左上角原点，pt）
    init(image: CGImage, scale: CGFloat, contentRect: CGRect, recordID: String?, showsShadow: Bool) {
        self.image = image
        self.scale = scale
        self.recordID = recordID
        state = PinState(
            imageSize: CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale),
            showsShadow: showsShadow,
        )
        pinView = PinView(frame: .zero)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        acceptsMouseMovedEvents = true
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        pinView.window_ = self
        contentView = pinView
        setContent(origin: contentRect.origin)
    }

    override var canBecomeKey: Bool {
        true
    }

    /// 贴图内容左上角的全局坐标
    var contentOrigin: CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: frame.minX + PinState.margin, y: primaryHeight - frame.maxY + PinState.margin)
    }

    /// 贴图内容的全局矩形
    var contentRect: CGRect {
        CGRect(origin: contentOrigin, size: state.contentSize)
    }

    func setContent(origin: CGPoint) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let size = state.windowSize
        let frame = CGRect(
            x: origin.x - PinState.margin,
            y: primaryHeight - (origin.y - PinState.margin) - size.height,
            width: size.width, height: size.height,
        )
        setFrame(frame, display: true)
        alphaValue = state.opacity
        pinView.needsDisplay = true
    }

    /// 修改状态后重新布局；anchor 为 nil 时保持中心不动
    func apply(_ change: (inout PinState) -> Void) {
        let oldRect = contentRect
        change(&state)
        let new = state.contentSize
        setContent(origin: CGPoint(x: oldRect.midX - new.width / 2, y: oldRect.midY - new.height / 2))
    }

    /// 以鼠标为中心连续缩放（触控板双指缩放），范围 10%～500%
    func zoom(by factor: CGFloat, at globalPoint: CGPoint) {
        zoom(at: globalPoint) { $0.zoom(by: factor, anchor: $1, contentOrigin: $2) }
    }

    /// 按步缩放（滚轮一格、- = 一次）：每步 5%
    func zoom(steps: Int, at globalPoint: CGPoint) {
        zoom(at: globalPoint) { $0.zoom(steps: steps, anchor: $1, contentOrigin: $2) }
    }

    private func zoom(at globalPoint: CGPoint, _ change: (inout PinState, CGPoint, CGPoint) -> CGPoint) {
        let rect = contentRect
        // 鼠标不在贴图上（按键缩放）时以中心为准
        let anchor = rect.contains(globalPoint)
            ? CGPoint(x: (globalPoint.x - rect.minX) / rect.width, y: (globalPoint.y - rect.minY) / rect.height)
            : CGPoint(x: 0.5, y: 0.5)
        setContent(origin: change(&state, anchor, rect.origin))
        pinView.flash("\(Int((state.zoom * 100).rounded()))%")
    }

    func setOpacity(_ value: CGFloat) {
        state.setOpacity(value)
        showOpacity()
    }

    func stepOpacity(_ steps: Int) {
        state.stepOpacity(steps)
        showOpacity()
    }

    private func showOpacity() {
        alphaValue = state.opacity
        pinView.flash("透明度 \(Int((state.opacity * 100).rounded()))%")
    }

    /// 编辑标注后换成新图（大小可能不变，位置保持）
    func replace(image: CGImage, scale: CGFloat) {
        let origin = contentOrigin
        self.image = image
        self.scale = scale
        state.imageSize = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        setContent(origin: origin)
    }

    /// 按当前旋转输出的图片（复制、保存用）
    var outputImage: CGImage {
        ImageRotation.rotated(image, quarterTurns: state.quarterTurns) ?? image
    }

    func perform(_ action: PinAction) {
        onAction(self, action)
    }
}
