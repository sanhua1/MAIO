import AppKit
import QuartzCore

/// 遮罩画布：冻结画面 + 选区外变暗 + 边框和手柄 + 尺寸标签 + 放大镜。
/// 全部用图层合成（不在 draw 里重画整张 5K 图），拖动时只改路径和位置，保持流畅（spec 5.3）。
/// 坐标是视图坐标（左下角原点）。
@MainActor
final class OverlayCanvas: NSView {
    static let dimColor = NSColor.black.withAlphaComponent(0.45).cgColor
    static let handleRadius: CGFloat = 4

    private let root = CALayer()
    private let imageLayer = CALayer()
    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let handlesLayer = CAShapeLayer()
    private let sizeBadge = BadgeLayer()
    let annotations = AnnotationLayer()
    /// 选中的标注：虚线框 + 手柄
    private let annotationOutline = CAShapeLayer()
    private let annotationHandles = CAShapeLayer()
    let magnifier = MagnifierLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        // 图层宿主视图：图层树完全由这里管理
        layer = root
        wantsLayer = true
        root.backgroundColor = NSColor.black.cgColor
        imageLayer.contentsGravity = .resize
        imageLayer.magnificationFilter = .nearest
        dimLayer.fillColor = Self.dimColor
        dimLayer.fillRule = .evenOdd
        borderLayer.fillColor = nil
        borderLayer.strokeColor = NSColor.controlAccentColor.cgColor
        borderLayer.lineWidth = 1.5
        handlesLayer.fillColor = NSColor.white.cgColor
        handlesLayer.strokeColor = NSColor.controlAccentColor.cgColor
        handlesLayer.lineWidth = 1.5
        annotations.isHidden = true
        annotations.masksToBounds = true
        annotations.needsDisplayOnBoundsChange = true
        annotationOutline.fillColor = nil
        annotationOutline.strokeColor = NSColor.white.cgColor
        annotationOutline.lineWidth = 1
        annotationOutline.lineDashPattern = [4, 3]
        annotationOutline.shadowOpacity = 0.6
        annotationOutline.shadowRadius = 1
        annotationOutline.shadowOffset = .zero
        annotationHandles.fillColor = NSColor.white.cgColor
        annotationHandles.strokeColor = NSColor.controlAccentColor.cgColor
        annotationHandles.lineWidth = 1
        let layers = [
            imageLayer, annotations, dimLayer, borderLayer, handlesLayer, annotationOutline, annotationHandles,
            sizeBadge, magnifier,
        ]
        for sublayer in layers {
            root.addSublayer(sublayer)
        }
        withoutAnimation { hideAll() }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    /// 只是画布，事件交给外层的 OverlayView
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        withoutAnimation {
            imageLayer.frame = bounds
            dimLayer.frame = bounds
            borderLayer.frame = bounds
            handlesLayer.frame = bounds
            annotationOutline.frame = bounds
            annotationHandles.frame = bounds
        }
    }

    func setImage(_ image: CGImage?, scale: CGFloat) {
        withoutAnimation {
            imageLayer.contents = image
            magnifier.image = image
            for layer in [root, imageLayer, sizeBadge, magnifier, annotations] {
                layer.contentsScale = scale
            }
            sizeBadge.textScale = scale
            magnifier.textScale = scale
        }
    }

    /// 选区外（或高亮窗口外）变暗；没有 hole 时整屏变暗。
    func render(hole: CGRect?, border: CGRect?, handles: [CGPoint]) {
        withoutAnimation {
            let path = CGMutablePath()
            path.addRect(bounds)
            if let hole {
                path.addRect(hole)
            }
            dimLayer.path = path
            borderLayer.path = border.map { CGPath(rect: $0.insetBy(dx: -0.75, dy: -0.75), transform: nil) }
            let dots = CGMutablePath()
            let radius = Self.handleRadius
            for point in handles {
                dots.addEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            }
            handlesLayer.path = handles.isEmpty ? nil : dots
        }
    }

    func renderSizeBadge(text: String?, frame: CGRect) {
        withoutAnimation {
            sizeBadge.isHidden = text == nil
            if let text {
                sizeBadge.text = text
                sizeBadge.frame = frame
            }
        }
    }

    func renderMagnifier(_ state: MagnifierLayer.State?, frame: CGRect) {
        withoutAnimation {
            magnifier.isHidden = state == nil
            if let state {
                magnifier.frame = frame
                magnifier.state = state
            }
        }
    }

    /// 标注图层只覆盖选区：画的是"选区底图 + 标注"，和输出完全一致
    func renderAnnotations(_ content: AnnotationLayer.Content?, frame: CGRect) {
        withoutAnimation {
            annotations.isHidden = content == nil
            guard let content else {
                annotations.content = nil
                return
            }
            annotations.frame = frame
            annotations.content = content
            annotations.setNeedsDisplay()
        }
    }

    /// 选中的标注：虚线包围框 + 手柄（视图坐标）
    func renderAnnotationSelection(outline: CGRect?, handles: [CGPoint]) {
        withoutAnimation {
            annotationOutline.path = outline.map { CGPath(rect: $0.insetBy(dx: -3, dy: -3), transform: nil) }
            let path = CGMutablePath()
            for point in handles {
                path.addRect(CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7))
            }
            annotationHandles.path = handles.isEmpty ? nil : path
        }
    }

    func hideAll() {
        renderAnnotations(nil, frame: .zero)
        renderAnnotationSelection(outline: nil, handles: [])
        render(hole: nil, border: nil, handles: [])
        renderSizeBadge(text: nil, frame: .zero)
        renderMagnifier(nil, frame: .zero)
    }

    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}

/// 选区内的"底图 + 标注"，用 AnnotationRenderer 绘制（和输出同一套代码）。
final class AnnotationLayer: CALayer {
    struct Content {
        var items: [Annotation]
        /// 这个图层覆盖的全局矩形（选区）
        var selection: CGRect
        var source: EffectSource
        var cache: EffectCache
    }

    var content: Content?

    override init() {
        super.init()
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func draw(in context: CGContext) {
        guard let content else { return }
        AnnotationRenderer.prepare(context, targetHeight: bounds.height, scale: 1, origin: content.selection.origin)
        AnnotationRenderer.drawComposite(
            content.items, selection: content.selection, source: content.source, cache: content.cache, in: context,
        )
    }
}

/// 带半透明背景的文字标签（尺寸标签）。
final class BadgeLayer: CALayer {
    static var font: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    }

    static let padding = CGSize(width: 6, height: 3)

    private let textLayer = CATextLayer()

    var text = "" {
        didSet { textLayer.string = NSAttributedString(string: text, attributes: Self.attributes) }
    }

    var textScale: CGFloat = 2 {
        didSet { textLayer.contentsScale = textScale }
    }

    static var attributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor.white]
    }

    static func size(for text: String) -> CGSize {
        let size = NSAttributedString(string: text, attributes: attributes).size()
        return CGSize(width: ceil(size.width) + padding.width * 2, height: ceil(size.height) + padding.height * 2)
    }

    override init() {
        super.init()
        backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        cornerRadius = 4
        addSublayer(textLayer)
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func layoutSublayers() {
        super.layoutSublayers()
        textLayer.frame = bounds.insetBy(dx: Self.padding.width, dy: Self.padding.height)
    }
}
