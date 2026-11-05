import Foundation
import Synchronization

/// 搜索结果里的一个文件
struct FileHit: Sendable, Equatable {
    var path: String
    var name: String
    var isDirectory: Bool
    var modified: Date
}

/// 索引的状态（设置页、结果列表顶部显示）
enum FileIndexState: Sendable, Equatable {
    case idle
    case loading
    case scanning(found: Int)
    case ready(count: Int, scannedAt: Date?)
    case failed(String)
}

/// 文件索引的总控：读盘或全盘扫描 → FSEvents 增量更新 → 定时存盘；搜索也在这里（和更新串行，不会读到改了一半的数据）。
///
/// 启动流程（参考 oil-find IndexManager.swift）：
/// 1. 读 `index.bin`，扫描设置和事件库都没变 → 立即可搜，从存盘时的事件编号回放离线期间的变化；
/// 2. 否则全盘扫描：**先记下当前事件编号并开始监视**，扫描期间的事件先攒着，扫完再补上，中间不漏。
actor FileIndex {
    static let saveInterval: TimeInterval = 30 * 60

    let file: URL
    private var options: ScanOptions
    private let devices = IndexConfiguration.devices()
    private let onState: @Sendable (FileIndexState) -> Void
    private var data: IndexData?
    private var watcher: FSEventsWatcher?
    private var scanner: FileScanner?
    /// 全盘扫描期间收到的事件
    private var pending: [FSEventsWatcher.Event] = []
    private var lastEventID: UInt64 = 0
    private var scannedAt: Date?
    private var dirty = false
    private var lastSave = Date()
    /// 最新一次搜索请求的编号：排队中的旧请求直接跳过
    nonisolated let latestSearch = Mutex(0)

    init(file: URL, options: ScanOptions, onState: @escaping @Sendable (FileIndexState) -> Void) {
        self.file = file
        self.options = options
        self.onState = onState
    }

    // MARK: 启动、停止

    func start() async {
        onState(.loading)
        let uuid = FSEventsWatcher.eventStoreUUID(forVolumeAt: "/System/Volumes/Data")
        if case let (header, loaded)? = Self.load(file),
           header.optionsHash == IndexConfiguration.fingerprint(options), header.eventStoreUUID == uuid {
            data = loaded
            lastEventID = header.lastEventID
            scannedAt = Date(timeIntervalSince1970: TimeInterval(header.savedAt))
            publishReady()
            startWatching(since: header.lastEventID)
            return
        }
        await rebuild()
    }

    private static func load(_ file: URL) -> (IndexPersistence.Header, IndexData)? {
        guard let loaded = try? IndexPersistence.load(from: file) else { return nil }
        return (loaded.header, loaded.data)
    }

    func stop() {
        watcher?.stop()
        watcher = nil
        scanner?.cancel()
        save(force: false)
    }

    /// 扫描设置变了（排除目录、权限）：换设置并重扫
    func update(options newOptions: ScanOptions) async {
        guard newOptions != options else { return }
        options = newOptions
        await rebuild()
    }

    /// 整盘重扫。旧索引在扫完前照常可搜
    func rebuild() async {
        guard scanner == nil else { return }
        let startID = FSEventsWatcher.currentEventID
        pending = []
        startWatching(since: startID)
        let scanner = FileScanner(options: options, devices: devices)
        self.scanner = scanner
        let progress = Task { [onState] in
            while !Task.isCancelled {
                onState(.scanning(found: Int(scanner.progress)))
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        let built = await Task.detached(priority: .utility) { () -> IndexData? in
            guard let result = scanner.scan("/", id: 0, inherited: EntryFlags.directory, firstID: 1) else { return nil }
            var fresh = IndexData.root()
            fresh.append(result.chunks, firstID: 1, endID: result.nextID)
            return fresh
        }.value
        progress.cancel()
        self.scanner = nil
        guard var fresh = built else { return }
        _ = IndexUpdater(options: options, devices: devices).apply(pending, to: &fresh)
        lastEventID = max(startID, pending.map(\.id).max() ?? 0)
        pending = []
        data = fresh
        scannedAt = Date()
        publishReady()
        save(force: true)
    }

    private func startWatching(since eventID: UInt64) {
        let watcher = watcher ?? FSEventsWatcher { [weak self] events in
            guard let self else { return }
            Task { await self.receive(events) }
        }
        let noisy = [
            "/private/var",
            "/private/tmp",
            "/Library/Caches",
            options.homePath + "/Library/Caches",
            options.homePath + "/Library/Logs",
            file.deletingLastPathComponent().path(percentEncoded: false),
        ]
        _ = watcher.start(paths: ["/"], since: eventID, excluding: noisy)
        self.watcher = watcher
    }

    // MARK: 增量更新

    private func receive(_ events: [FSEventsWatcher.Event]) async {
        guard scanner == nil, var current = data else {
            pending += events
            return
        }
        data = nil // 修改期间不持有第二份引用，避免整份复制
        let outcome = IndexUpdater(options: options, devices: devices).apply(events, to: &current)
        data = current
        lastEventID = max(lastEventID, events.map(\.id).max() ?? 0)
        switch outcome {
        case let .applied(changed):
            dirty = dirty || changed
            if changed {
                publishReady()
            }
            if Date().timeIntervalSince(lastSave) > Self.saveInterval {
                save(force: false)
            }
        case .needsFullRescan:
            await rebuild()
        }
    }

    // MARK: 搜索

    /// `token` 不是最新的请求时返回 nil（用户已经接着打字了）
    func search(_ query: FileQuery, limit: Int, token: Int) -> (hits: [FileHit], total: Int)? {
        guard latestSearch.withLock({ $0 }) == token, let data else { return nil }
        let result = data.search(query, limit: limit, now: UInt32(Date().timeIntervalSince1970))
        let hits = result.ids.map { id in
            FileHit(
                path: data.path(id), name: data.name(id), isDirectory: data.flags[Int(id)] & EntryFlags.directory != 0,
                modified: Date(timeIntervalSince1970: TimeInterval(data.mtimes[Int(id)])),
            )
        }
        return (hits, result.total)
    }

    // MARK: 存盘

    func save(force: Bool) {
        guard let data, force || dirty else { return }
        let compact = data.compacted()
        if compact.count != data.count {
            self.data = compact
        }
        let header = IndexPersistence.Header(
            optionsHash: IndexConfiguration.fingerprint(options), lastEventID: lastEventID,
            eventStoreUUID: FSEventsWatcher.eventStoreUUID(forVolumeAt: "/System/Volumes/Data"),
            savedAt: UInt64((scannedAt ?? Date()).timeIntervalSince1970),
        )
        do {
            try IndexPersistence.save(compact, header: header, to: file)
            dirty = false
            lastSave = Date()
        } catch {
            onState(.failed("索引存盘失败：\(error.localizedDescription)"))
        }
    }

    private func publishReady() {
        onState(.ready(count: data?.liveCount ?? 0, scannedAt: scannedAt))
    }
}
