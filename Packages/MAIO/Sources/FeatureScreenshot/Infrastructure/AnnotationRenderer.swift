import AppKit

/// 冻结画面的来源：用来画底图、马赛克和模糊。
struct EffectSource: @unchecked Sendable {
    let image: CGImage
    /// 这张图左上角的全局坐标（pt）
    let origin: CGPoint
    /// 每 pt 的像素数
    let scale: CGFloat

    /// 全局矩形在这张图里的像素矩形（已裁到图片范围内）
    func pixelRect(for rect: CGRect) -> CGRect {
        let pixels = CGRect(
            x: ((rect.minX - origin.x) * scale).rounded(.down),
            y: ((rect.minY - origin.y) * scale).rounded(.down),
            width: (rect.width * scale).rounded(.up),
            height: (rect.height * scale).rounded(.up),
        )
        return pixels.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }

    /// 像素矩形对应的全局矩形
    func globalRect(forPixels pixels: CGRect) -> CGRect {
        CGRect(
            x: origin.x + pixels.minX / scale, y: origin.y + pixels.minY / scale,
            width: pixels.width / scale, height: pixels.height / scale,
        )
    }
}

/// 画标注。屏幕上的显示和最终输出用同一套代码，保证"看到的就是得到的"（spec P2 验收）。
///
/// 约定：调用前 context 的坐标系已经设置成"全局坐标、左上角原点、单位 pt"（见 `prepare`）。
enum AnnotationRenderer {
    /// 把 context 设置成全局坐标：targetHeight 是目标的高度（context 自己的单位），
    /// scale 是每 pt 对应多少个 context 单位，origin 是目标左上角的全局坐标。
    static func prepare(_ context: CGContext, targetHeight: CGFloat, scale: CGFloat, origin: CGPoint) {
        context.translateBy(x: 0, y: targetHeight)
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -origin.x, y: -origin.y)
    }

    /// 底图（选区内的冻结画面）+ 全部标注
    static func drawComposite(
        _ items: [Annotation], selection: CGRect, source: EffectSource, cache: EffectCache, in context: CGContext,
    ) {
        let pixels = source.pixelRect(for: selection)
        if !pixels.isNull, let base = source.image.cropping(to: pixels) {
            drawImage(base, in: source.globalRect(forPixels: pixels), context: context, smooth: false)
        }
        // 马赛克、模糊只处理截图本身，先画；其他标注始终画在它们上面，不会被模糊掉
        let effects = items.filter(\.isEffect)
        for annotation in effects + items.filter({ !$0.isEffect }) {
            context.saveGState()
            draw(annotation, source: source, cache: cache, in: context)
            context.restoreGState()
        }
    }

    /// 输出：选区裁剪 + 标注，按物理像素
    static func renderOutput(_ items: [Annotation], selection: CGRect, source: EffectSource) -> CGImage? {
        let pixels = source.pixelRect(for: selection)
        guard !pixels.isNull, pixels.width >= 1, pixels.height >= 1 else { return nil }
        let space = source.image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard let space, let context = CGContext(
            data: nil, width: Int(pixels.width), height: Int(pixels.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue,
        ) else { return nil }
        let rect = source.globalRect(forPixels: pixels)
        prepare(context, targetHeight: pixels.height, scale: source.scale, origin: rect.origin)
        drawComposite(items, selection: rect, source: source, cache: EffectCache(), in: context)
        return context.makeImage()
    }

    // MARK: 单个对象

    static func draw(_ annotation: Annotation, source: EffectSource?, cache: EffectCache, in context: CGContext) {
        let color = cgColor(annotation.color)
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(annotation.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        switch annotation.shape {
        case let .rectangle(frame, filled, rounded):
            let radius = rounded ? min(6 + annotation.lineWidth, frame.width / 4, frame.height / 4) : 0
            context.setLineJoin(rounded ? .round : .miter)
            context.addPath(CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.drawPath(using: filled ? .fill : .stroke)
        case let .ellipse(frame, filled):
            context.addEllipse(in: frame)
            context.drawPath(using: filled ? .fill : .stroke)
        case let .line(from, to, dashed):
            if dashed {
                context.setLineDash(phase: 0, lengths: [annotation.lineWidth * 3, annotation.lineWidth * 2.5])
            }
            context.strokeLineSegments(between: [from, to])
        case let .arrow(from, to):
            drawArrow(from: from, to: to, width: annotation.lineWidth, in: context)
        case let .pen(points):
            context.addPath(smoothPath(points))
            context.strokePath()
        case let .highlighter(points):
            // 正片叠底：下面的文字仍然可读
            context.setBlendMode(.multiply)
            context.setLineCap(.square)
            context.addPath(smoothPath(points))
            context.strokePath()
        case let .text(box):
            TextRendering.draw(box, color: annotation.color, in: context)
        case let .counter(center, number, radius):
            drawCounter(center: center, number: number, radius: radius, color: annotation.color, in: context)
        case .mosaic, .blur:
            drawEffect(annotation.shape, source: source, cache: cache, in: context)
        }
    }

    private static func drawEffect(
        _ shape: AnnotationShape, source: EffectSource?, cache: EffectCache, in context: CGContext,
    ) {
        guard let source else { return }
        switch shape {
        case let .mosaic(frame, block):
            if let image = cache.mosaic(frame, block: block, source: source) {
                drawImage(image.image, in: image.rect, context: context, smooth: false)
            }
        case let .blur(frame, radius):
            if let image = cache.blur(frame, radius: radius, source: source) {
                drawImage(image.image, in: image.rect, context: context, smooth: true)
            }
        default:
            break
        }
    }

    /// 在左上角原点的坐标系里画图片（CGContext 画图默认是左下角原点，要局部翻转）
    static func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext, smooth: Bool) {
        context.saveGState()
        context.interpolationQuality = smooth ? .high : .none
        context.translateBy(x: 0, y: rect.minY + rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: rect)
        context.restoreGState()
    }

    static func cgColor(_ color: AnnotationColor) -> CGColor {
        CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    /// 平滑路径：经过相邻两点中点的二次曲线
    static func smoothPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            path.addLine(to: points.last ?? first)
            return path
        }
        for index in 1 ..< points.count - 1 {
            let control = points[index]
            let next = points[index + 1]
            path.addQuadCurve(to: CGPoint(x: (control.x + next.x) / 2, y: (control.y + next.y) / 2), control: control)
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    /// 箭头：实心三角形箭头，大小随粗细变化
    private static func drawArrow(from: CGPoint, to: CGPoint, width: CGFloat, in context: CGContext) {
        let length = hypot(to.x - from.x, to.y - from.y)
        guard length > 0 else { return }
        let headLength = min(max(10, width * 4), length)
        let headWidth = headLength * 0.85
        let ux = (to.x - from.x) / length
        let uy = (to.y - from.y) / length
        let base = CGPoint(x: to.x - ux * headLength, y: to.y - uy * headLength)
        // 线身只画到箭头底部稍里面，避免圆头从箭头两侧露出来
        let shaftEnd = CGPoint(x: to.x - ux * headLength * 0.6, y: to.y - uy * headLength * 0.6)
        context.strokeLineSegments(between: [from, shaftEnd])
        context.move(to: to)
        context.addLine(to: CGPoint(x: base.x - uy * headWidth / 2, y: base.y + ux * headWidth / 2))
        context.addLine(to: CGPoint(x: base.x + uy * headWidth / 2, y: base.y - ux * headWidth / 2))
        context.closePath()
        context.fillPath()
    }

    private static func drawCounter(
        center: CGPoint,
        number: Int,
        radius: CGFloat,
        color: AnnotationColor,
        in context: CGContext,
    ) {
        let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fillEllipse(in: circle)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
        context.setLineWidth(max(1, radius / 8))
        context.strokeEllipse(in: circle.insetBy(dx: radius / 16, dy: radius / 16))
        TextRendering.drawCentered(
            "\(number)",
            in: circle,
            fontSize: radius * 1.05,
            color: TextRendering.contrasting(color),
            context: context,
        )
    }
}

extension Annotation {
    /// 马赛克、模糊
    var isEffect: Bool {
        switch shape {
        case .mosaic, .blur: true
        default: false
        }
    }
}
