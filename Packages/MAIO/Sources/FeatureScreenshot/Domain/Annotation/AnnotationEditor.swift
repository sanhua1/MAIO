import CoreGraphics
import Foundation

/// 标注编辑的鼠标状态机（纯逻辑，可单测）：画新对象、选中、移动、拖手柄、改样式。
/// 坐标是全局坐标（左上角原点，pt）。
struct AnnotationEditor {
    enum Drag: Equatable {
        case drawing(start: CGPoint)
        case moving(original: Annotation, start: CGPoint, saved: Bool)
        case resizing(AnnotationHandle, original: Annotation, saved: Bool)
    }

    enum Outcome: Equatable {
        /// 不归标注处理（交给选区：移动、调整、新建）
        case notHandled
        case handled
        /// 在这里开始输入新文字
        case beginText(CGPoint)
        /// 重新编辑这条文字
        case editText(UUID)
    }

    var document = AnnotationDocument()
    /// 当前工具；nil 表示没有选工具（单击选中对象）
    private(set) var tool: AnnotationTool?
    /// 文字工具：色板改文字颜色还是背景色。外观为"无"时只能改文字颜色
    var textColorTarget = TextColorTarget.foreground
    var style = ToolStyle()
    /// 正在画的对象（松开鼠标后才加入文档）
    private(set) var draft: Annotation?
    private(set) var drag: Drag?

    var isDragging: Bool {
        drag != nil
    }

    /// 工具栏显示哪个工具的选项：选中的对象优先，其次是当前工具
    var activeTool: AnnotationTool? {
        document.selected?.tool ?? tool
    }

    /// 所有要显示的对象（包括正在画的）
    var visibleItems: [Annotation] {
        draft.map { document.items + [$0] } ?? document.items
    }

    // MARK: 鼠标

    mutating func mouseDown(at point: CGPoint, clickCount: Int, selection: CGRect) -> Outcome {
        if let selected = document.selected {
            if let handle = selected.handle(at: point) {
                drag = .resizing(handle, original: selected, saved: false)
                return .handled
            }
            if selected.contains(point) {
                // 双击文字，或者文字工具下单击文字：重新编辑
                if clickCount >= 2 || tool == .text, case .text = selected.shape {
                    return .editText(selected.id)
                }
                drag = .moving(original: selected, start: point, saved: false)
                return .handled
            }
        }
        if clickCount >= 2, let hit = document.hit(at: point), case .text = hit.shape {
            document.selectedID = hit.id
            return .editText(hit.id)
        }
        guard let tool else {
            if let hit = document.hit(at: point) {
                document.selectedID = hit.id
                drag = .moving(original: hit, start: point, saved: false)
                return .handled
            }
            document.selectedID = nil
            return .notHandled
        }
        // 文字工具单击已有的文字：重新编辑
        if tool == .text, let hit = document.hit(at: point), case .text = hit.shape {
            document.selectedID = hit.id
            return .editText(hit.id)
        }
        document.selectedID = nil
        guard selection.contains(point) else { return .notHandled }
        return begin(tool, at: point)
    }

    mutating func mouseDragged(to point: CGPoint, constrained: Bool) {
        switch drag {
        case let .drawing(start):
            draft = draft.map { updateDraft($0, start: start, point: point, constrained: constrained) }
        case let .moving(original, start, saved):
            if !saved {
                document.checkpoint()
                drag = .moving(original: original, start: start, saved: true)
            }
            document.replace(original.moved(by: CGVector(dx: point.x - start.x, dy: point.y - start.y)))
        case let .resizing(handle, original, saved):
            if !saved {
                document.checkpoint()
                drag = .resizing(handle, original: original, saved: true)
            }
            let target = constrained ? constrainedPoint(for: original, handle: handle, point: point) : point
            document.replace(original.resized(handle, to: target))
        case nil:
            break
        }
    }

    mutating func mouseUp() {
        defer {
            drag = nil
            draft = nil
        }
        guard case .drawing = drag, let draft, draft.isMeaningful else { return }
        document.add(draft)
        // 画完自动选中，方便马上改颜色、粗细
        document.selectedID = draft.id
    }

    // MARK: 工具与样式

    /// 选择工具；再选一次同一个工具表示取消
    mutating func select(tool newTool: AnnotationTool?) {
        tool = newTool == tool ? nil : newTool
        document.selectedID = nil
    }

    // MARK: 键盘

    mutating func deleteSelected() -> Bool {
        guard let id = document.selectedID else { return false }
        document.remove(id: id)
        return true
    }

    /// Esc 的前两层：取消选中对象 → 取消工具。返回 false 表示这一层没有可退出的
    mutating func escape() -> Bool {
        if document.selectedID != nil {
            document.selectedID = nil
            return true
        }
        if tool != nil {
            tool = nil
            return true
        }
        return false
    }

    mutating func adjustCounter(by delta: Int) {
        document.counterAdjustment = max(document.counterAdjustment + delta, -document.highestCounterNumber)
    }

    // MARK: 内部

    private mutating func begin(_ tool: AnnotationTool, at point: CGPoint) -> Outcome {
        let color = style.color(for: tool)
        let size = CGFloat(style.size(for: tool))
        switch tool {
        case .text:
            return .beginText(point)
        case .counter:
            let number = document.nextCounterNumber
            document.add(Annotation(shape: .counter(center: point, number: number, radius: size), color: color, lineWidth: 0))
            document.counterAdjustment = 0
            return .handled
        default:
            let empty = CGRect(origin: point, size: .zero)
            let shape: AnnotationShape = switch tool {
            case .rectangle: .rectangle(empty, filled: style.filled, rounded: style.rounded)
            case .ellipse: .ellipse(empty, filled: style.filled)
            case .arrow: .arrow(from: point, to: point)
            case .line: .line(from: point, to: point, dashed: style.dashed)
            case .pen: .pen([point])
            case .highlighter: .highlighter([point])
            case .mosaic: .mosaic(empty, blockSize: size)
            default: .blur(empty, radius: size)
            }
            draft = Annotation(shape: shape, color: color, lineWidth: size)
            drag = .drawing(start: point)
            return .handled
        }
    }

    private func updateDraft(_ draft: Annotation, start: CGPoint, point: CGPoint, constrained: Bool) -> Annotation {
        var copy = draft
        let squared = constrained ? Snapping.square(from: start, to: point) : point
        let angled = constrained ? Snapping.angle(from: start, to: point) : point
        let frame = SelectionGeometry.rect(from: start, to: squared)
        switch draft.shape {
        case let .rectangle(_, filled, rounded): copy.shape = .rectangle(frame, filled: filled, rounded: rounded)
        case let .ellipse(_, filled): copy.shape = .ellipse(frame, filled: filled)
        case let .mosaic(_, block): copy.shape = .mosaic(SelectionGeometry.rect(from: start, to: point), blockSize: block)
        case let .blur(_, radius): copy.shape = .blur(SelectionGeometry.rect(from: start, to: point), radius: radius)
        case .arrow: copy.shape = .arrow(from: start, to: angled)
        case let .line(_, _, dashed): copy.shape = .line(from: start, to: angled, dashed: dashed)
        case let .pen(points): copy.shape = .pen(Self.appending(point, to: points))
        case let .highlighter(points):
            // ⇧ 画水平直线
            copy.shape = .highlighter(constrained
                ? [start, CGPoint(x: point.x, y: start.y)]
                : Self.appending(point, to: points))
        case .text, .counter: break
        }
        return copy
    }

    /// 拖手柄时按住 ⇧：直线、箭头吸附角度
    private func constrainedPoint(for annotation: Annotation, handle: AnnotationHandle, point: CGPoint) -> CGPoint {
        switch (annotation.shape, handle) {
        case let (.arrow(from, _), .end), let (.line(from, _, _), .end): Snapping.angle(from: from, to: point)
        case let (.arrow(_, to), .start), let (.line(_, to, _), .start): Snapping.angle(from: to, to: point)
        default: point
        }
    }

    /// 画笔：和上一个点距离太近时不加（减少点数），路径平滑交给渲染
    private static func appending(_ point: CGPoint, to points: [CGPoint]) -> [CGPoint] {
        guard let last = points.last, hypot(point.x - last.x, point.y - last.y) < 1 else { return points + [point] }
        return points
    }

    mutating func updateSelected(coalescing key: String? = nil, _ change: (inout Annotation) -> Void) {
        guard var annotation = document.selected else { return }
        let before = annotation
        change(&annotation)
        guard annotation != before else { return }
        document.checkpoint(coalescing: key.map { "\($0)-\(annotation.id)" })
        document.replace(annotation)
    }
}
