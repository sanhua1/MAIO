import CoreGraphics

/// 选中的标注上可以拖动的手柄
enum AnnotationHandle: Equatable, Sendable {
    /// 矩形类（矩形、椭圆、马赛克、模糊）的 8 个手柄
    case frame(SelectionHandle)
    /// 直线、箭头的起点和终点
    case start
    case end
}

/// 标注的包围盒、点击判定、移动、调整。
extension Annotation {
    /// 对应的工具（选中对象后用来决定工具栏显示哪些选项）
    var tool: AnnotationTool {
        switch shape {
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .arrow: .arrow
        case .line: .line
        case .pen: .pen
        case .highlighter: .highlighter
        case .text: .text
        case .mosaic: .mosaic
        case .blur: .blur
        case .counter: .counter
        }
    }

    var bounds: CGRect {
        let half = lineWidth / 2
        switch shape {
        case let .rectangle(frame, _, _), let .ellipse(frame, _):
            return frame.insetBy(dx: -half, dy: -half)
        case let .mosaic(frame, _), let .blur(frame, _):
            return frame
        case let .arrow(from, to), let .line(from, to, _):
            return SelectionGeometry.rect(from: from, to: to).insetBy(dx: -lineWidth * 2, dy: -lineWidth * 2)
        case let .pen(points), let .highlighter(points):
            return Self.boundingBox(points).insetBy(dx: -half, dy: -half)
        case let .text(box):
            return box.frame
        case let .counter(center, _, radius):
            return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        }
    }

    /// 点击判定：线条类按到线的距离，实心和区域类按范围
    func contains(_ point: CGPoint, tolerance: CGFloat = 4) -> Bool {
        let reach = tolerance + lineWidth / 2
        switch shape {
        case let .rectangle(frame, filled, _):
            let outer = frame.insetBy(dx: -reach, dy: -reach)
            let inner = frame.insetBy(dx: reach, dy: reach)
            return outer.contains(point) && (filled || inner.isNull || inner.isEmpty || !inner.contains(point))
        case let .ellipse(frame, filled):
            return Self.ellipse(frame, contains: point, filled: filled, reach: reach)
        case let .arrow(from, to), let .line(from, to, _):
            return Self.distance(from: point, toSegment: from, to) <= reach
        case let .pen(points), let .highlighter(points):
            return Self.distance(from: point, toPolyline: points) <= reach
        case .text, .mosaic, .blur:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case let .counter(center, _, radius):
            return hypot(point.x - center.x, point.y - center.y) <= radius + tolerance
        }
    }

    func moved(by delta: CGVector) -> Annotation {
        var copy = transformed(offset: delta, scale: 1)
        copy.id = id
        return copy
    }

    var handles: [(AnnotationHandle, CGPoint)] {
        switch shape {
        case let .rectangle(frame, _, _), let .ellipse(frame, _), let .mosaic(frame, _), let .blur(frame, _):
            SelectionHandle.allCases.map { (.frame($0), $0.point(in: frame)) }
        case let .arrow(from, to), let .line(from, to, _):
            [(.start, from), (.end, to)]
        case .pen, .highlighter, .text, .counter:
            []
        }
    }

    func handle(at point: CGPoint, tolerance: CGFloat = SelectionGeometry.handleTolerance) -> AnnotationHandle? {
        handles.first { abs($0.1.x - point.x) <= tolerance && abs($0.1.y - point.y) <= tolerance }?.0
    }

    /// 拖动手柄后的对象（从按下时的原始对象计算）
    func resized(_ handle: AnnotationHandle, to point: CGPoint) -> Annotation {
        var copy = self
        switch (shape, handle) {
        case let (.rectangle(frame, filled, rounded), .frame(side)):
            copy.shape = .rectangle(SelectionGeometry.resize(frame, handle: side, to: point), filled: filled, rounded: rounded)
        case let (.ellipse(frame, filled), .frame(side)):
            copy.shape = .ellipse(SelectionGeometry.resize(frame, handle: side, to: point), filled: filled)
        case let (.mosaic(frame, block), .frame(side)):
            copy.shape = .mosaic(SelectionGeometry.resize(frame, handle: side, to: point), blockSize: block)
        case let (.blur(frame, radius), .frame(side)):
            copy.shape = .blur(SelectionGeometry.resize(frame, handle: side, to: point), radius: radius)
        case let (.arrow(_, to), .start): copy.shape = .arrow(from: point, to: to)
        case let (.arrow(from, _), .end): copy.shape = .arrow(from: from, to: point)
        case let (.line(_, to, dashed), .start): copy.shape = .line(from: point, to: to, dashed: dashed)
        case let (.line(from, _, dashed), .end): copy.shape = .line(from: from, to: point, dashed: dashed)
        default: break
        }
        return copy
    }

    /// 太小的对象（手抖的单击）不保留
    var isMeaningful: Bool {
        switch shape {
        case let .rectangle(frame, _, _), let .ellipse(frame, _), let .mosaic(frame, _), let .blur(frame, _):
            frame.width >= 2 && frame.height >= 2
        case let .arrow(from, to), let .line(from, to, _):
            hypot(to.x - from.x, to.y - from.y) >= 2
        case let .pen(points), let .highlighter(points):
            !points.isEmpty
        case let .text(box):
            !box.string.isEmpty
        case .counter:
            true
        }
    }

    // MARK: 几何辅助

    static func boundingBox(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { rect, point in
            rect.union(CGRect(origin: point, size: .zero))
        }
    }

    static func distance(from point: CGPoint, toSegment start: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let t = min(max(((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared, 0), 1)
        return hypot(point.x - (start.x + t * dx), point.y - (start.y + t * dy))
    }

    static func distance(from point: CGPoint, toPolyline points: [CGPoint]) -> CGFloat {
        guard let first = points.first else { return .infinity }
        guard points.count > 1 else { return hypot(point.x - first.x, point.y - first.y) }
        return zip(points, points.dropFirst()).map { distance(from: point, toSegment: $0, $1) }.min() ?? .infinity
    }

    private static func ellipse(_ frame: CGRect, contains point: CGPoint, filled: Bool, reach: CGFloat) -> Bool {
        let rx = frame.width / 2
        let ry = frame.height / 2
        guard rx > 0, ry > 0 else { return false }
        let outer = pow((point.x - frame.midX) / (rx + reach), 2) + pow((point.y - frame.midY) / (ry + reach), 2)
        guard outer <= 1 else { return false }
        if filled || rx <= reach || ry <= reach {
            return true
        }
        let inner = pow((point.x - frame.midX) / (rx - reach), 2) + pow((point.y - frame.midY) / (ry - reach), 2)
        return inner >= 1
    }
}
