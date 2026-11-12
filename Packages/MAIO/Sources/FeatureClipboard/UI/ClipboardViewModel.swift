import AppKit
import Observation

/// 空格预览的内容。图片条目和图片文件都带一张大图，预览时直接显示。
struct ClipPreviewContent {
    let item: ClipItem
    let payload: ClipPayload
    let image: NSImage?
    /// 原图的像素尺寸（显示在右上角）
    let pixelSize: CGSize?
}

/// 弹出列表的状态：搜索、选择、预览，以及缩略图 / 图标缓存。
@MainActor
@Observable
final class ClipboardViewModel {
    /// 列表最多加载这么多条（更早的通过搜索找到）
    static let pageSize = 300

    private(set) var picker = PickerState()
    var query = "" {
        didSet { scheduleReload() }
    }

    /// 正在预览的条目内容
    private(set) var preview: ClipPreviewContent?
    private(set) var thumbnails: [Int64: NSImage] = [:]
    /// 每次打开时加一，用于让搜索框重新获得焦点、列表滚到顶部
    private(set) var openToken = 0

    @ObservationIgnored var onPaste: ((ClipItem, Bool) -> Void)?
    /// 右键菜单里需要面板控制器处理的操作（复制、贴图、翻译）
    @ObservationIgnored var onAction: ((ClipItem, ClipRowAction) -> Void)?
    @ObservationIgnored var onClose: (() -> Void)?
    @ObservationIgnored private let store: ClipStore
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    /// 正在读取缩略图的条目，避免同一行反复请求
    @ObservationIgnored private var loadingThumbnails: Set<Int64> = []
    @ObservationIgnored private var icons: [String: NSImage] = [:]

    init(store: ClipStore) {
        self.store = store
    }

    /// 正在搜索（搜索框有焦点、打字进搜索框）。不在搜索时按键由面板控制器直接处理
    var isSearching = false
    private(set) var searchMode: ClipboardSettings.SearchMode = .explicit
    /// 这次按键时输入法正在组字（拼音还没上屏）：⏎、空格、⌫、方向键、Esc 都是输入法的，搜索框不处理
    @ObservationIgnored var keyIsComposing = false

    /// 每次弹出时调用：清空搜索、选中第一条
    /// 搜索时也搜图片里识别出的文字（设置开关）
    private var searchesImageText = true

    func prepareForOpen(searchMode: ClipboardSettings.SearchMode, searchImageText: Bool) {
        self.searchMode = searchMode
        searchesImageText = searchImageText
        isSearching = searchMode == .typeToSearch
        preview = nil
        openToken += 1
        if query.isEmpty {
            reload(keepSelection: false)
        } else {
            query = ""
        }
    }

    func reload(keepSelection: Bool = false) {
        reloadTask?.cancel()
        let query = query
        let imageText = searchesImageText
        reloadTask = Task { [weak self, store] in
            guard let items = try? await store.items(matching: query, limit: Self.pageSize, includeImageText: imageText),
                  !Task.isCancelled
            else { return }
            self?.picker.setItems(items, keepSelection: keepSelection)
        }
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    // MARK: 操作

    func startSearch() {
        preview = nil
        isSearching = true
    }

    /// 结束搜索：保留搜索结果，之后的按键用来选择和粘贴
    func endSearch(clear: Bool) {
        if clear {
            query = ""
        }
        isSearching = false
    }

    func move(by offset: Int) {
        picker.move(by: offset)
        refreshPreview()
    }

    func select(_ index: Int) {
        picker.select(index)
        refreshPreview()
    }

    func pasteSelected(plainText: Bool) {
        guard let item = picker.selected else { return }
        onPaste?(item, plainText)
    }

    func pasteQuick(slot: Int) {
        guard let item = picker.quickItem(slot: slot) else { return }
        onPaste?(item, false)
    }

    func deleteSelected() {
        guard let item = picker.selected else { return }
        picker.remove(item.id)
        thumbnails[item.id] = nil
        loadingThumbnails.remove(item.id)
        Task { [store] in try? await store.delete([item.id]) }
        refreshPreview()
    }

    func togglePinSelected() {
        guard let item = picker.selected else { return }
        Task { [weak self, store] in
            try? await store.setPinned(item.id, !item.isPinned)
            self?.reload(keepSelection: true)
        }
    }

    /// 右键菜单：先选中这一条，再执行
    func perform(_ action: ClipRowAction, on item: ClipItem) {
        if let index = picker.items.firstIndex(where: { $0.id == item.id }) {
            select(index)
        }
        switch action {
        case .paste: pasteSelected(plainText: false)
        case .pastePlainText: pasteSelected(plainText: true)
        case .preview: togglePreview()
        case .togglePin: togglePinSelected()
        case .delete: deleteSelected()
        case .copy, .pinToScreen, .translate: onAction?(item, action)
        }
    }

    func togglePreview() {
        if preview != nil {
            preview = nil
        } else {
            showPreview()
        }
    }

    private func refreshPreview() {
        if preview != nil {
            showPreview()
        }
    }

    private func showPreview() {
        // 方向键连按时只保留最后一次：前一次的预览结果直接丢掉
        previewTask?.cancel()
        guard let item = picker.selected else {
            preview = nil
            return
        }
        previewTask = Task { [weak self, store] in
            guard let payload = try? await store.payload(item.id), !Task.isCancelled else { return }
            let loaded = await store.previewImage(for: item, payload: payload)
            guard !Task.isCancelled else { return }
            self?.preview = ClipPreviewContent(
                item: item, payload: payload, image: loaded?.image, pixelSize: loaded?.pixelSize,
            )
        }
    }

    // MARK: 图片

    func thumbnail(for item: ClipItem) -> NSImage? {
        if let cached = thumbnails[item.id] {
            return cached
        }
        guard item.hasThumbnail, loadingThumbnails.insert(item.id).inserted else { return nil }
        Task { [weak self, store] in
            let data = try? await store.thumbnail(item.id)
            self?.loadingThumbnails.remove(item.id)
            guard let data, let image = NSImage(data: data) else { return }
            self?.thumbnails[item.id] = image
        }
        return nil
    }

    func icon(forApp bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = icons[bundleID] {
            return cached
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = icon
        return icon
    }
}

/// 剪贴板历史一条的右键菜单操作
enum ClipRowAction {
    case paste
    case pastePlainText
    /// 只写回剪贴板，不粘贴
    case copy
    /// 钉到屏幕上（通过截图功能的契约）
    case pinToScreen
    /// 交给翻译窗口（通过翻译功能的契约）
    case translate
    case preview
    case togglePin
    case delete
}
