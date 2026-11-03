import CoreGraphics

/// 截图时的鼠标交互状态机（纯逻辑，可单测）：框选、移动、调整大小、单击选中高亮的窗口。
/// 所有坐标都是全局坐标（左上角原点，pt）。
struct CaptureInteraction {
    enum Drag: Equatable {
        /// 新建选区。`previous` 是按下前的选区：没有拖出足够距离就松手时恢复它
        case creating(start: CGPoint, previous: CGRect?)
        case moving(original: CGRect, start: CGPoint)
        case resizing(SelectionHandle, original: CGRect)
    }

    enum Effect: Equatable {
        case none
        /// 复制并结束
        case confirm
        /// 退出截图
        case exit
    }

    /// 拖动超过这个距离（pt）才算框选，否则算单击
    static let dragThreshold: CGFloat = 3

    /// 当前选区
    private(set) var selection: CGRect?
    /// 选区所在显示器的范围（选区不能跨显示器）
    private(set) var bounds: CGRect = .zero
    private(set) var drag: Drag?
    /// 是否已经拖出了选区（用于区分单击和框选）
    private var didDragOut = false
    /// 新建选区时按下处的显示器范围（真正拖出选区后才替换 bounds）
    private var pendingBounds: CGRect = .zero

    var isDragging: Bool {
        drag != nil
    }

    var isCreating: Bool {
        if case .creating = drag {
            return true
        }
        return false
    }

    mutating func mouseDown(at point: CGPoint, clickCount: Int, displayBounds: CGRect) -> Effect {
        if let selection {
            if clickCount >= 2, selection.contains(point) {
                return .confirm
            }
            if let handle = SelectionGeometry.handle(at: point, in: selection) {
                drag = .resizing(handle, original: selection)
                return .none
            }
            if selection.contains(point) {
                drag = .moving(original: selection, start: point)
                return .none
            }
        }
        drag = .creating(start: point, previous: selection)
        didDragOut = false
        if selection == nil {
            bounds = displayBounds
        }
        pendingBounds = displayBounds
        return .none
    }

    mutating func mouseDragged(to point: CGPoint) {
        switch drag {
        case let .creating(start, _):
            let distance = hypot(point.x - start.x, point.y - start.y)
            guard didDragOut || distance >= Self.dragThreshold else { return }
            didDragOut = true
            bounds = pendingBounds
            let end = SelectionGeometry.clamp(point, to: bounds)
            selection = SelectionGeometry.rect(from: SelectionGeometry.clamp(start, to: bounds), to: end)
        case let .moving(original, start):
            let delta = CGVector(dx: point.x - start.x, dy: point.y - start.y)
            selection = SelectionGeometry.move(original, by: delta, within: bounds)
        case let .resizing(handle, original):
            let target = SelectionGeometry.clamp(point, to: bounds)
            selection = SelectionGeometry.resize(original, handle: handle, to: target)
        case nil:
            break
        }
    }

    /// 松开鼠标。`highlighted` 是鼠标下高亮的窗口或控件：没有选区时单击就选中它。
    mutating func mouseUp(highlighted: CGRect?) {
        defer { drag = nil }
        guard case let .creating(_, previous) = drag, !didDragOut else {
            dropEmptySelection()
            return
        }
        if let previous {
            selection = previous
        } else if let highlighted {
            bounds = pendingBounds
            selection = SelectionGeometry.clamp(highlighted, to: bounds)
            dropEmptySelection()
        }
    }

    /// 右键：有选区时取消选区，没有时退出
    mutating func cancel() -> Effect {
        drag = nil
        guard selection != nil else { return .exit }
        selection = nil
        return .none
    }

    mutating func select(_ rect: CGRect, displayBounds: CGRect) {
        drag = nil
        bounds = displayBounds
        selection = SelectionGeometry.clamp(rect, to: displayBounds)
        dropEmptySelection()
    }

    mutating func nudge(dx: CGFloat, dy: CGFloat, resize: Bool) {
        guard let selection, drag == nil else { return }
        self.selection = SelectionGeometry.nudge(selection, dx: dx, dy: dy, resize: resize, within: bounds)
    }

    private mutating func dropEmptySelection() {
        if let selection, selection.width < 1 || selection.height < 1 {
            self.selection = nil
        }
    }
}
