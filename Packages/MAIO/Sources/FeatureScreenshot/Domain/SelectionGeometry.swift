import CoreGraphics

/// 选区的 8 个手柄。坐标系统一使用全局坐标（原点在主屏左上角，单位 pt），与 CGWindowList、辅助功能一致。
enum SelectionHandle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    var movesLeft: Bool {
        [.topLeft, .left, .bottomLeft].contains(self)
    }

    var movesRight: Bool {
        [.topRight, .right, .bottomRight].contains(self)
    }

    var movesTop: Bool {
        [.topLeft, .top, .topRight].contains(self)
    }

    var movesBottom: Bool {
        [.bottomLeft, .bottom, .bottomRight].contains(self)
    }
}

/// 选区的几何运算：手柄判定、调整大小、移动、限制范围、像素对齐。
enum SelectionGeometry {
    /// 手柄的点击容差（pt）
    static let handleTolerance: CGFloat = 7

    static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    /// 鼠标处的手柄。选区太小时只判定四个角，避免手柄互相重叠。
    static func handle(at point: CGPoint, in rect: CGRect, tolerance: CGFloat = handleTolerance) -> SelectionHandle? {
        let small = rect.width < tolerance * 4 || rect.height < tolerance * 4
        let candidates = small ? [.topLeft, .topRight, .bottomRight, .bottomLeft] : SelectionHandle.allCases
        return candidates.first { handle in
            let center = handle.point(in: rect)
            return abs(center.x - point.x) <= tolerance && abs(center.y - point.y) <= tolerance
        }
    }

    /// 拖动手柄后的选区。始终从按下时的原始选区计算，拖过对边时自动翻转。
    static func resize(_ original: CGRect, handle: SelectionHandle, to point: CGPoint) -> CGRect {
        var minX = original.minX, maxX = original.maxX, minY = original.minY, maxY = original.maxY
        if handle.movesLeft {
            minX = point.x
        }
        if handle.movesRight {
            maxX = point.x
        }
        if handle.movesTop {
            minY = point.y
        }
        if handle.movesBottom {
            maxY = point.y
        }
        return rect(from: CGPoint(x: minX, y: minY), to: CGPoint(x: maxX, y: maxY))
    }

    /// 平移选区，整体保持在 bounds 内（不改变大小）。
    static func move(_ rect: CGRect, by delta: CGVector, within bounds: CGRect) -> CGRect {
        var moved = rect.offsetBy(dx: delta.dx, dy: delta.dy)
        moved.origin.x = min(max(moved.minX, bounds.minX), max(bounds.minX, bounds.maxX - moved.width))
        moved.origin.y = min(max(moved.minY, bounds.minY), max(bounds.minY, bounds.maxY - moved.height))
        return moved
    }

    static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let clipped = rect.intersection(bounds)
        return clipped.isNull ? CGRect(origin: bounds.origin, size: .zero) : clipped
    }

    static func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    /// 对齐到物理像素（scale = 每 pt 的像素数），输出图片不会出现半个像素。
    static func pixelAligned(_ rect: CGRect, scale: CGFloat) -> CGRect {
        guard scale > 0 else { return rect }
        let minX = (rect.minX * scale).rounded() / scale
        let minY = (rect.minY * scale).rounded() / scale
        let maxX = (rect.maxX * scale).rounded() / scale
        let maxY = (rect.maxY * scale).rounded() / scale
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// 选区（全局 pt）在某个显示器截图里对应的像素矩形。
    static func pixelRect(of rect: CGRect, displayBounds: CGRect, scale: CGFloat) -> CGRect {
        let local = rect.offsetBy(dx: -displayBounds.minX, dy: -displayBounds.minY)
        return CGRect(
            x: (local.minX * scale).rounded(),
            y: (local.minY * scale).rounded(),
            width: (local.width * scale).rounded(),
            height: (local.height * scale).rounded(),
        )
    }

    /// 方向键微调：移动，或者（resize 为 true 时）调整右边和下边。
    static func nudge(_ rect: CGRect, dx: CGFloat, dy: CGFloat, resize: Bool, within bounds: CGRect) -> CGRect {
        if resize {
            let width = max(1 / 4, rect.width + dx)
            let height = max(1 / 4, rect.height + dy)
            return clamp(CGRect(origin: rect.origin, size: CGSize(width: width, height: height)), to: bounds)
        }
        return move(rect, by: CGVector(dx: dx, dy: dy), within: bounds)
    }
}
