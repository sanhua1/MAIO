import CoreServices
import Foundation

// 参考：references/oil-find/Sources/OilFindCore/FSWatcher.swift、references/cardinal/cardinal-sdk（MIT）
/// 监视整个磁盘的文件变化（FSEvents，逐个文件的事件）。可以从某个事件编号开始回放离线期间的变化。
final class FSEventsWatcher: @unchecked Sendable {
    struct Event: Sendable {
        var path: String
        var flags: UInt32
        var id: UInt64
    }

    static let sinceNow = UInt64(kFSEventStreamEventIdSinceNow)

    private let handler: @Sendable ([Event]) -> Void
    private let queue = DispatchQueue(label: "app.maio.launcher.fsevents", qos: .utility)
    private var stream: FSEventStreamRef?

    init(handler: @escaping @Sendable ([Event]) -> Void) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    /// 开始监视。`excluding` 最多 8 个目录（系统限制），这些目录下的事件系统直接不发
    func start(paths: [String], since eventID: UInt64, latency: Double = 0.15, excluding: [String] = []) -> Bool {
        stop()
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil,
        )
        let flags =
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, Self.callback, &context, paths as CFArray, eventID, latency, flags,
        ) else { return false }
        if !excluding.isEmpty {
            FSEventStreamSetExclusionPaths(stream, Array(excluding.prefix(8)) as CFArray)
        }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return false
        }
        self.stream = stream
        return true
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private static let callback: FSEventStreamCallback = { _, info, count, paths, flags, ids in
        guard let info else { return }
        let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()
        let list = unsafeBitCast(paths, to: NSArray.self)
        var events: [Event] = []
        events.reserveCapacity(count)
        for index in 0 ..< count {
            guard let path = list[index] as? String else { continue }
            events.append(Event(path: path, flags: flags[index], id: ids[index]))
        }
        watcher.handler(events)
    }

    /// 当前最新的事件编号（全盘扫描开始前记下，扫完从这里接着处理）
    static var currentEventID: UInt64 {
        FSEventsGetCurrentEventId()
    }

    /// 某个卷的事件库 UUID。系统重建事件库后，旧的事件编号就不能用了
    static func eventStoreUUID(forVolumeAt path: String) -> String {
        var info = stat()
        guard stat(path, &info) == 0, let uuid = FSEventsCopyUUIDForDevice(info.st_dev),
              let text = CFUUIDCreateString(nil, uuid)
        else { return "" }
        return text as String
    }
}

extension FSEventsWatcher.Event {
    private func has(_ flag: Int) -> Bool {
        flags & UInt32(flag) != 0
    }

    /// 回放完离线期间的历史事件（这一条没有路径意义）
    var isHistoryDone: Bool {
        has(kFSEventStreamEventFlagHistoryDone)
    }

    /// 这条路径下面的内容要整个重读（系统合并或丢弃了事件）
    var mustRescanSubtree: Bool {
        has(kFSEventStreamEventFlagMustScanSubDirs) || has(kFSEventStreamEventFlagUserDropped)
            || has(kFSEventStreamEventFlagKernelDropped)
    }

    /// 只能整盘重扫：监视的根变了、事件编号回绕
    var requiresFullRescan: Bool {
        has(kFSEventStreamEventFlagRootChanged) || has(kFSEventStreamEventFlagEventIdsWrapped)
    }

    /// 目录被创建或移动过来：里面的内容没有单独的事件，要扫一遍
    var directoryAppeared: Bool {
        has(kFSEventStreamEventFlagItemIsDir)
            && (has(kFSEventStreamEventFlagItemCreated) || has(kFSEventStreamEventFlagItemRenamed))
    }
}
