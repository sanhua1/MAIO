import AppKit
import MAIOUI
import SwiftUI

/// 截图历史面板的状态（spec F11、4.7）。
@MainActor @Observable
final class HistoryBrowserModel {
    struct Actions {
        var pin: (String) -> Void
        var copy: (String) -> Void
        var edit: (String) -> Void
        /// 识别文字；参数二为 true 时直接翻译
        var recognize: (String, Bool) -> Void
    }

    let store: ScreenshotHistoryStore
    let actions: Actions
    var records: [ScreenshotRecord] = []
    var query = ""
    var selection: String?
    var stats: ScreenshotHistoryStore.Stats?
    var thumbnails: [String: NSImage] = [:]
    /// 每条记录的最终图（拖出去时要同步拿到路径）
    private var imageURLs: [String: URL] = [:]

    init(store: ScreenshotHistoryStore, actions: Actions) {
        self.store = store
        self.actions = actions
    }

    var groups: [HistorySearch.DayGroup] {
        HistorySearch.groupByDay(HistorySearch.filter(records, query: query))
    }

    func reload() async {
        records = await store.records
        stats = await store.stats
        var urls: [String: URL] = [:]
        for record in records {
            urls[record.id] = await store.finalImageURL(for: record)
        }
        imageURLs = urls
        let ids = Set(records.map(\.id))
        thumbnails = thumbnails.filter { ids.contains($0.key) }
    }

    func thumbnail(for id: String) async -> NSImage? {
        if let cached = thumbnails[id] {
            return cached
        }
        let url = await store.thumbnailURL(for: id)
        let image = await Task.detached { NSImage(contentsOf: url) }.value
        thumbnails[id] = image
        return image
    }

    func delete(_ id: String) async {
        try? await store.delete([id])
        if selection == id {
            selection = nil
        }
        await reload()
    }

    func togglePinned(_ record: ScreenshotRecord) async {
        try? await store.setPinned(!record.pinned, id: record.id)
        await reload()
    }

    /// 拖到访达、聊天窗口：拖的是临时副本（`HistoryDragCopy`），不是历史目录里的文件
    func dragItem(for record: ScreenshotRecord) -> NSItemProvider {
        guard let source = imageURLs[record.id], let copy = HistoryDragCopy.make(from: source, date: record.createdAt) else {
            return NSItemProvider()
        }
        let provider = NSItemProvider(object: copy as NSURL)
        provider.suggestedName = copy.deletingPathExtension().lastPathComponent
        return provider
    }

    func reveal(_ id: String) async {
        let folder = await store.folder(for: id)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}

/// 截图历史面板：按日期分组的缩略图网格。双击贴图，⌘C 复制，E 重新编辑标注，⌫ 删除，拖出去是图片文件。
struct HistoryBrowser: View {
    @Bindable var model: HistoryBrowserModel
    @FocusState private var gridFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.groups.isEmpty {
                ContentUnavailableView(
                    model.query.isEmpty ? "还没有截图" : "没有找到", systemImage: "photo.on.rectangle",
                    description: Text(model.query.isEmpty ? "按 ⌥F1 截图后会出现在这里" : "可以按日期（2026-11-03）、来源 App 或识别出的文字搜索"),
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                grid
            }
        }
        .frame(minWidth: 560, minHeight: 420)
        .task { await model.reload() }
    }

    private var header: some View {
        HStack {
            TextField("搜索：日期、来源 App、识别出的文字", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
            Spacer()
            if let stats = model.stats {
                Text("\(stats.count) 张 · \(ByteCountFormatter.string(fromByteCount: stats.bytes, countStyle: .decimal))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(10)
    }

    private var grid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14, pinnedViews: [.sectionHeaders]) {
                ForEach(model.groups) { group in
                    Section {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 10)], spacing: 10) {
                            ForEach(group.records) { record in
                                HistoryCell(model: model, record: record, isSelected: model.selection == record.id)
                            }
                        }
                    } header: {
                        Text(group.day.formatted(date: .complete, time: .omitted))
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .background(.bar)
                    }
                }
            }
            .padding(10)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($gridFocused)
        .onKeyPress(keys: [.delete, .deleteForward]) { _ in
            guard let id = model.selection else { return .ignored }
            Task { await model.delete(id) }
            return .handled
        }
        .onKeyPress(.return) {
            guard let id = model.selection else { return .ignored }
            model.actions.pin(id)
            return .handled
        }
        .onKeyPress(characters: .init(charactersIn: "eEcC")) { press in
            guard let id = model.selection else { return .ignored }
            if press.characters.lowercased() == "e", press.modifiers.isEmpty {
                model.actions.edit(id)
                return .handled
            }
            if press.characters.lowercased() == "c", press.modifiers == .command {
                model.actions.copy(id)
                return .handled
            }
            return .ignored
        }
    }
}

private struct HistoryCell: View {
    let model: HistoryBrowserModel
    let record: ScreenshotRecord
    let isSelected: Bool
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else {
                        Color.secondary.opacity(0.1)
                    }
                }
                .frame(height: 110)
                .frame(maxWidth: .infinity)
                if record.pinned {
                    Image(systemName: "star.fill").foregroundStyle(.yellow).padding(4)
                }
            }
            Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(6)
        .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear, in: .rect(cornerRadius: 8))
        .contentShape(.rect)
        .onTapGesture(count: 2) { model.actions.pin(record.id) }
        .onTapGesture { model.selection = record.id }
        // 拖到访达、微信等聊天窗口（和拖一个 png 文件一样）
        .onDrag { model.dragItem(for: record) }
        .contextMenu { menu }
        .task(id: record.id) { image = await model.thumbnail(for: record.id) }
    }

    private var caption: String {
        let time = record.createdAt.formatted(date: .omitted, time: .shortened)
        return "\(time) · \(record.pixelWidth)×\(record.pixelHeight)"
    }

    @ViewBuilder private var menu: some View {
        Button("贴图") { model.actions.pin(record.id) }
        Button("复制") { model.actions.copy(record.id) }
        Button("编辑标注") { model.actions.edit(record.id) }
        Button("识别文字") { model.actions.recognize(record.id, false) }
        Button("翻译") { model.actions.recognize(record.id, true) }
        Divider()
        Button(record.pinned ? "取消收藏" : "收藏（不会被自动清理）") { Task { await model.togglePinned(record) } }
        Button("在访达中显示") { Task { await model.reveal(record.id) } }
        Divider()
        Button("删除", role: .destructive) { Task { await model.delete(record.id) } }
    }
}

/// 截图历史窗口
@MainActor
final class HistoryWindowController {
    private let model: HistoryBrowserModel
    private var window: NSWindow?

    init(store: ScreenshotHistoryStore, actions: HistoryBrowserModel.Actions) {
        model = HistoryBrowserModel(store: store, actions: actions)
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        AppActivation.activateForcibly()
        window.makeKeyAndOrderFront(nil)
        Task { await model.reload() }
    }

    func reload() {
        Task { await model.reload() }
    }

    func close() {
        window?.close()
        window = nil
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false,
        )
        window.title = "截图历史"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: HistoryBrowser(model: model))
        window.center()
        return window
    }
}
