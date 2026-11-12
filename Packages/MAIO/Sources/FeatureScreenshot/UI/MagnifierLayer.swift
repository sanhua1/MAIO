import AppKit
import QuartzCore

/// 放大镜（spec 4.1）：15×15 个物理像素放大 8 倍，中心格子是鼠标处的像素；下方显示坐标和颜色。
final class MagnifierLayer: CALayer {
    struct State: Equatable {
        /// 鼠标处的像素（冻结图里的像素坐标，左上角原点）
        var pixelX: Int
        var pixelY: Int
        var lines: [String]
        /// 最下面的按键提示（整行宽度，不和色块对齐）
        var hints: [String] = []
        var color: CGColor?
    }

    static let pixels = 15
    static let cell: CGFloat = 8
    static var zoomSide: CGFloat {
        CGFloat(pixels) * cell
    }

    static let infoHeight: CGFloat = 54
    /// 按键提示区的高度（两行）
    static let hintHeight: CGFloat = 30
    static var size: CGSize {
        CGSize(width: zoomSide, height: zoomSide + infoHeight + hintHeight)
    }

    private let zoom = ZoomLayer()
    private let info = CATextLayer()
    private let hint = CATextLayer()
    private let swatch = CALayer()

    var image: CGImage? {
        didSet { zoom.image = image }
    }

    var textScale: CGFloat = 2 {
        didSet {
            info.contentsScale = textScale
            hint.contentsScale = textScale
            zoom.contentsScale = textScale
        }
    }

    var state: State? {
        didSet {
            guard let state, state != oldValue else { return }
            zoom.pixelX = state.pixelX
            zoom.pixelY = state.pixelY
            zoom.setNeedsDisplay()
            info.string = NSAttributedString(string: state.lines.joined(separator: "\n"), attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.white,
            ])
            hint.string = NSAttributedString(string: state.hints.joined(separator: "\n"), attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.white.withAlphaComponent(0.75),
            ])
            swatch.backgroundColor = state.color
        }
    }

    override init() {
        super.init()
        backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        cornerRadius = 6
        masksToBounds = true
        borderColor = NSColor.white.withAlphaComponent(0.6).cgColor
        borderWidth = 1
        zoom.magnificationFilter = .nearest
        swatch.borderColor = NSColor.white.cgColor
        swatch.borderWidth = 1
        info.isWrapped = true
        hint.isWrapped = true
        for sublayer in [zoom, swatch, info, hint] {
            addSublayer(sublayer)
        }
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
        let side = Self.zoomSide
        // 图层坐标左下角原点：放大区域在上，文字在下
        zoom.frame = CGRect(x: 0, y: bounds.height - side, width: side, height: side)
        // 从下往上：按键提示 → 坐标和颜色 → 放大区域
        let hintTop = Self.hintHeight
        swatch.frame = CGRect(x: 6, y: hintTop + Self.infoHeight - 20, width: 12, height: 12)
        info.frame = CGRect(x: 24, y: hintTop + 2, width: bounds.width - 28, height: Self.infoHeight - 6)
        hint.frame = CGRect(x: 6, y: 2, width: bounds.width - 8, height: Self.hintHeight - 2)
    }
}

/// 放大区域：直接从冻结图裁出 15×15 像素，用最近邻放大绘制，再画十字中心格。
private final class ZoomLayer: CALayer {
    var image: CGImage?
    var pixelX = 0
    var pixelY = 0

    override func draw(in context: CGContext) {
        context.setFillColor(NSColor.black.cgColor)
        context.fill(bounds)
        let count = MagnifierLayer.pixels
        let cell = bounds.width / CGFloat(count)
        let half = count / 2
        let requested = CGRect(x: pixelX - half, y: pixelY - half, width: count, height: count)
        if let image {
            let valid = requested.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            if !valid.isNull, let crop = image.cropping(to: valid) {
                // 裁剪用左上角原点的像素坐标；绘制用左下角原点，所以 y 要换算
                let drawRect = CGRect(
                    x: (valid.minX - requested.minX) * cell,
                    y: (requested.maxY - valid.maxY) * cell,
                    width: valid.width * cell,
                    height: valid.height * cell,
                )
                context.interpolationQuality = .none
                context.draw(crop, in: drawRect)
            }
        }
        let center = CGRect(x: CGFloat(half) * cell, y: CGFloat(half) * cell, width: cell, height: cell)
        context.setStrokeColor(NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(cell)
        context.move(to: CGPoint(x: 0, y: center.midY))
        context.addLine(to: CGPoint(x: center.minX, y: center.midY))
        context.move(to: CGPoint(x: center.maxX, y: center.midY))
        context.addLine(to: CGPoint(x: bounds.width, y: center.midY))
        context.move(to: CGPoint(x: center.midX, y: 0))
        context.addLine(to: CGPoint(x: center.midX, y: center.minY))
        context.move(to: CGPoint(x: center.midX, y: center.maxY))
        context.addLine(to: CGPoint(x: center.midX, y: bounds.height))
        context.strokePath()
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1)
        context.stroke(center.insetBy(dx: 0.5, dy: 0.5))
    }
}
