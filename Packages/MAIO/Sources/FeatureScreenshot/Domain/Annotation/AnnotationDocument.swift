import CoreGraphics
import Foundation

/// 标注对象列表 + 选中 + 快照式撤销 / 重做（spec 4.2：每次修改前保存整个列表，最多 100 步）。
struct AnnotationDocument: Equatable {
    static let undoLimit = 100

    private(set) var items: [Annotation] = []
    var selectedID: UUID?
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []
    /// 上一次快照的合并键：连续的同类修改（拖滑块、滚轮调大小）只保存一次快照
    private var lastCoalescingKey: String?
    /// 用滚轮调整的"下一个序号"偏移，放下一个序号后清零
    var counterAdjustment = 0

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    var canRedo: Bool {
        !redoStack.isEmpty
    }

    var isEmpty: Bool {
        items.isEmpty
    }

    var selected: Annotation? {
        selectedID.flatMap { id in items.first { $0.id == id } }
    }

    var highestCounterNumber: Int {
        items.compactMap { annotation -> Int? in
            if case let .counter(_, number, _) = annotation.shape {
                return number
            }
            return nil
        }.max() ?? 0
    }

    /// 下一个序号：已有的最大序号 + 1，再加上滚轮调整
    var nextCounterNumber: Int {
        max(1, highestCounterNumber + 1 + counterAdjustment)
    }

    /// 修改前调用，保存一份快照。coalescing 相同的连续调用只保存第一次（合并成一步撤销）
    mutating func checkpoint(coalescing key: String? = nil) {
        defer { lastCoalescingKey = key }
        if let key, key == lastCoalescingKey {
            return
        }
        undoStack.append(items)
        if undoStack.count > Self.undoLimit {
            undoStack.removeFirst(undoStack.count - Self.undoLimit)
        }
        redoStack.removeAll()
    }

    /// 载入已有的标注（重新编辑时），不进撤销记录
    mutating func load(_ annotations: [Annotation]) {
        items = annotations
        undoStack.removeAll()
        redoStack.removeAll()
        selectedID = nil
    }

    mutating func add(_ annotation: Annotation) {
        checkpoint()
        items.append(annotation)
    }

    /// 替换同 id 的对象，不保存快照（拖动时由调用方在开始时保存一次）
    mutating func replace(_ annotation: Annotation) {
        guard let index = items.firstIndex(where: { $0.id == annotation.id }) else { return }
        items[index] = annotation
    }

    mutating func remove(id: UUID) {
        guard items.contains(where: { $0.id == id }) else { return }
        checkpoint()
        items.removeAll { $0.id == id }
        if selectedID == id {
            selectedID = nil
        }
    }

    mutating func undo() {
        lastCoalescingKey = nil
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(items)
        items = previous
        dropMissingSelection()
    }

    mutating func redo() {
        lastCoalescingKey = nil
        guard let next = redoStack.popLast() else { return }
        undoStack.append(items)
        items = next
        dropMissingSelection()
    }

    /// 最上层的、包含这个点的对象
    func hit(at point: CGPoint) -> Annotation? {
        items.last { $0.contains(point) }
    }

    private mutating func dropMissingSelection() {
        if let selectedID, !items.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
    }
}
