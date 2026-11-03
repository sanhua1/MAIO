/// 弹出列表的选择状态（纯逻辑）。列表顺序：未固定的按最后使用时间从新到旧，固定的排在最后。
/// 默认选中第一条（最近复制或最近粘贴的）。
struct PickerState: Sendable, Equatable {
    private(set) var items: [ClipItem] = []
    private(set) var selectedIndex = 0

    /// 快速粘贴的编号（⌘1…⌘9、⌘0）只给前 10 条未固定的条目
    static let quickSlots = 10

    static func arrange(_ items: [ClipItem]) -> [ClipItem] {
        let recent = items.filter { !$0.isPinned }.sorted { $0.lastUsedAt > $1.lastUsedAt }
        let pinned = items.filter(\.isPinned).sorted { $0.createdAt < $1.createdAt }
        return recent + pinned
    }

    /// 替换列表（例如搜索结果变化）。keepSelection 为 true 时尽量保持选中同一条。
    mutating func setItems(_ newItems: [ClipItem], keepSelection: Bool = false) {
        let previous = selected?.id
        items = Self.arrange(newItems)
        if keepSelection, let previous, let index = items.firstIndex(where: { $0.id == previous }) {
            selectedIndex = index
        } else {
            selectedIndex = 0
        }
    }

    var selected: ClipItem? {
        items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }

    mutating func select(_ index: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = min(max(index, 0), items.count - 1)
    }

    /// 上下移动，到头后循环
    mutating func move(by offset: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = ((selectedIndex + offset) % items.count + items.count) % items.count
    }

    /// 快速粘贴编号对应的条目：slot 1…9 为第 1…9 条，0 为第 10 条
    func quickItem(slot: Int) -> ClipItem? {
        let index = slot == 0 ? 9 : slot - 1
        let recent = items.filter { !$0.isPinned }
        return recent.indices.contains(index) ? recent[index] : nil
    }

    /// 某一行显示的快速粘贴编号（没有则 nil）
    func quickSlot(of item: ClipItem) -> Int? {
        guard !item.isPinned, let index = items.firstIndex(where: { $0.id == item.id }), index < Self.quickSlots
        else { return nil }
        return index == 9 ? 0 : index + 1
    }

    mutating func remove(_ id: ClipItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: index)
        if selectedIndex >= items.count {
            selectedIndex = max(0, items.count - 1)
        }
    }
}
