import Foundation
import Observation

/// 面板的状态：输入、来源标签、结果、选中项。
@MainActor
@Observable
final class LauncherViewModel {
    var query = "" {
        didSet {
            if query != oldValue {
                refresh(resetSelection: true)
            }
        }
    }

    /// 标签选中的来源（输入前缀时实际来源以前缀为准，见 `parsed`）
    var selectedSource: LauncherSource = .all {
        didSet {
            if selectedSource != oldValue {
                refresh(resetSelection: true)
            }
        }
    }

    private(set) var sections: [LauncherSection] = []
    private(set) var items: [LauncherItem] = []
    private(set) var selectedIndex = 0
    private(set) var parsed = LauncherQuery(source: .all, text: "", engine: nil)
    /// 每次打开面板加一，视图据此把焦点给搜索框、滚到顶部
    private(set) var openToken = 0

    var apps: [LauncherItem] = [] {
        didSet { refresh(resetSelection: false) }
    }

    /// MAIO 命令、系统操作、系统设置面板（每次打开面板时更新）
    var commands: [LauncherItem] = [] {
        didSet {
            if commands != oldValue {
                refresh(resetSelection: false)
            }
        }
    }

    var usage = UsageBook()
    var settings = LauncherSettings.defaultValue
    private var running: Set<String> = []
    /// 文件搜索（没开文件搜索时是 nil）
    var files: FileSearchClient?
    private(set) var fileResults = FileResults()
    /// 文件索引的状态（建索引时在结果里显示进度）
    var fileState: FileIndexState = .idle
    let icons = IconCache()

    /// 打开选中项（第二个参数：是否改为在 Finder 中显示）
    var onOpen: ((LauncherItem, Bool) -> Void)?
    var onClose: (() -> Void)?

    var selected: LauncherItem? {
        items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }

    /// 文件索引还没准备好时，标签栏右侧显示的说明
    var fileStatusText: String? {
        guard files != nil, parsed.source.includesFiles else { return nil }
        switch fileState {
        case .loading: return "正在读取文件索引…"
        case let .scanning(found): return "正在建立文件索引：已找到 \(found.formatted()) 个"
        case let .failed(message): return message
        case .idle, .ready: return nil
        }
    }

    /// 标签上高亮的来源
    var effectiveSource: LauncherSource {
        parsed.source
    }

    func prepareForOpen(keepQuery: Bool, running: Set<String>) {
        self.running = running
        if !keepQuery {
            query = ""
            selectedSource = .all
        }
        refresh(resetSelection: !keepQuery)
        openToken += 1
    }

    func refresh(resetSelection: Bool) {
        let previous = parsed
        parsed = LauncherQuery.parse(query, selected: selectedSource, engines: settings.engines)
        if parsed != previous || resetSelection {
            requestFiles()
        }
        rebuild(resetSelection: resetSelection)
    }

    /// 输入或来源变了：搜文件（结果异步到达，到了再刷新列表；在那之前先显示上一次的文件结果）
    private func requestFiles() {
        guard let files, parsed.source.includesFiles, parsed.engine == nil, !parsed.isEmpty else {
            files?.cancel()
            fileResults = FileResults()
            return
        }
        let limit = parsed.source == .all ? settings.maxFilesInAll : Self.maxFilesInSource
        files.search(parsed.text, foldersOnly: parsed.source == .folders, limit: limit) { [weak self] results in
            guard let self, results.query == parsed.text else { return }
            fileResults = results
            rebuild(resetSelection: false)
        }
    }

    static let maxFilesInSource = 300

    private func rebuild(resetSelection: Bool) {
        let shownFiles = parsed.source.includesFiles && !parsed.isEmpty && parsed.engine == nil ? fileResults : FileResults()
        let ranking = LauncherRanking(
            apps: apps, commands: commands, files: shownFiles, usage: usage, running: running, settings: settings, now: Date(),
        )
        sections = ranking.sections(for: parsed)
        let previous = selected?.id
        items = sections.flatMap(\.items)
        if resetSelection {
            selectedIndex = 0
        } else {
            selectedIndex = items.firstIndex { $0.id == previous } ?? 0
        }
    }

    func move(by delta: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + items.count) % items.count
    }

    func select(_ index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
    }

    func openSelected(reveal: Bool) {
        guard let selected else { return }
        onOpen?(selected, reveal)
    }

    /// ⌘1～⌘9
    func openQuick(slot: Int) {
        guard (1 ... 9).contains(slot), items.indices.contains(slot - 1) else { return }
        selectedIndex = slot - 1
        openSelected(reveal: false)
    }

    /// Tab / ⇧Tab：在已实现的来源之间循环。输入里写了前缀时，先去掉前缀再切换。
    func cycleSource(forward: Bool) {
        let sources = LauncherSource.available
        let current = sources.firstIndex(of: parsed.source) ?? 0
        let next = sources[(current + (forward ? 1 : sources.count - 1)) % sources.count]
        if parsed.source != selectedSource || parsed.engine != nil {
            query = parsed.text
        }
        selectedSource = next
    }

    /// Esc：有输入先清空，再按一次关闭
    func escape() {
        if !query.isEmpty {
            query = ""
        } else if selectedSource != .all {
            selectedSource = .all
        } else {
            onClose?()
        }
    }

    /// 输入为空时按 ⌫：回到"全部"
    func deleteOnEmpty() -> Bool {
        guard query.isEmpty, selectedSource != .all else { return false }
        selectedSource = .all
        return true
    }

    func record(_ item: LauncherItem) {
        usage.record(item.id, query: parsed.text, at: Date())
    }
}
