import Darwin
import Foundation

/// 扫描设置
struct ScanOptions: Sendable, Equatable {
    /// 不进入的目录（完整路径）
    var excludedPaths: Set<String>
    /// 不进入的目录（任何位置，按名称）
    var excludedNames: Set<String>
    /// 进入 .app 等包的内部
    var indexPackageContents = false
    var threads = 4
    /// 用户目录（里面的条目带 `inHome`）
    var homePath = NSHomeDirectory()
}

/// 一个线程扫到的记录（编号不连续，合并时按编号放回）
struct ScanChunk: Sendable {
    var ids: [UInt32] = []
    var parents: [UInt32] = []
    var flags: [UInt8] = []
    var sizes: [UInt32] = []
    var mtimes: [UInt32] = []
    var nameLengths: [UInt32] = []
    /// 名称（NFC 原文）首尾相接
    var names: [UInt8] = []
}

// 参考：references/oil-find/Sources/OilFindCore/Scanner.swift（MIT，Copyright (c) 2026 Lin Zhihuang）
/// 多线程扫描一个目录树。线程共用一个目录任务栈（后进先出，内存占用小）；
/// 子项的编号在父目录之后分配，所以**父目录的编号总是小于子项**（整个索引依赖这一点）。
final class FileScanner: @unchecked Sendable {
    private struct Task {
        var path: String
        var id: UInt32
        /// 子项继承的标志
        var inherited: UInt8
    }

    let options: ScanOptions
    /// 只扫这些设备（系统卷 + 数据卷），不跨进其他挂载点
    private let devices: Set<Int32>
    private let condition = NSCondition()
    private var tasks: [Task] = []
    private var active = 0
    private var nextID: UInt32 = 0
    private var cancelled = false

    init(options: ScanOptions, devices: Set<Int32>) {
        self.options = options
        self.devices = devices
    }

    /// 已经分配了多少编号（用于显示进度）
    var progress: UInt32 {
        condition.lock()
        defer { condition.unlock() }
        return nextID
    }

    func cancel() {
        condition.lock()
        cancelled = true
        condition.broadcast()
        condition.unlock()
    }

    /// 扫描 `path` 下面的所有内容（不含 `path` 本身）。子项编号从 `firstID` 开始。取消时返回 nil。
    func scan(_ path: String, id: UInt32, inherited: UInt8, firstID: UInt32) -> (chunks: [ScanChunk], nextID: UInt32)? {
        condition.lock()
        tasks = [Task(path: path, id: id, inherited: inherited)]
        nextID = firstID
        active = 0
        condition.unlock()
        let threads = max(1, options.threads)
        let slots = ChunkSlots(count: threads)
        DispatchQueue.concurrentPerform(iterations: threads) { worker in
            slots[worker] = work()
        }
        condition.lock()
        defer { condition.unlock() }
        return cancelled ? nil : (slots.all, nextID)
    }

    private func work() -> ScanChunk {
        var chunk = ScanChunk()
        var reader = DirectoryReader()
        defer { reader.deallocate() }
        var entries: [DirectoryReader.Entry] = []
        while let task = nextTask() {
            let children = process(task, reader: &reader, entries: &entries, into: &chunk)
            condition.lock()
            tasks.append(contentsOf: children)
            active -= 1
            condition.broadcast()
            condition.unlock()
        }
        return chunk
    }

    /// 取一个目录；没有任务且没有线程在干活（不会再有新任务）时返回 nil
    private func nextTask() -> Task? {
        condition.lock()
        defer { condition.unlock() }
        while tasks.isEmpty, active > 0, !cancelled {
            condition.wait()
        }
        guard !cancelled, let task = tasks.popLast() else { return nil }
        active += 1
        return task
    }

    private var isCancelled: Bool {
        condition.lock()
        defer { condition.unlock() }
        return cancelled
    }

    private func reserve(_ count: Int) -> UInt32 {
        condition.lock()
        defer { condition.unlock() }
        let base = nextID
        nextID &+= UInt32(count)
        return base
    }

    private func process(
        _ task: Task, reader: inout DirectoryReader, entries: inout [DirectoryReader.Entry], into chunk: inout ScanChunk,
    ) -> [Task] {
        let descriptor = open(task.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return [] }
        defer { close(descriptor) }
        var children: [Task] = []
        while !isCancelled, reader.read(descriptor, into: &entries) {
            let accepted = entries.filter { $0.error == 0 && !Self.isDotEntry($0.name) }
            let base = reserve(accepted.count)
            for (offset, entry) in accepted.enumerated() {
                let id = base + UInt32(offset)
                let name = Self.nfc(entry.name)
                let flags = flags(of: entry, name: name, inherited: task.inherited)
                chunk.append(id: id, parent: task.id, flags: flags, entry: entry, name: name)
                if let child = descend(entry, name: name, flags: flags, parent: task, id: id) {
                    children.append(child)
                }
            }
        }
        return children
    }

    private func flags(of entry: DirectoryReader.Entry, name: [UInt8], inherited: UInt8) -> UInt8 {
        Self.entryFlags(isDirectory: entry.type == VDIR.rawValue, name: name, bsdFlags: entry.bsdFlags, inherited: inherited)
    }

    /// 一条记录的标志：从父目录继承的 + 自己的（扫描和增量更新共用）
    static func entryFlags(isDirectory: Bool, name: [UInt8], bsdFlags: UInt32, inherited: UInt8) -> UInt8 {
        var flags = inherited & EntryFlags.inherited
        if name.first == UInt8(ascii: ".") || bsdFlags & UInt32(UF_HIDDEN) != 0 {
            flags |= EntryFlags.hidden
        }
        if bsdFlags & UInt32(SF_DATALESS) != 0 {
            flags |= EntryFlags.dataless
        }
        guard isDirectory else { return flags }
        flags |= EntryFlags.directory
        let text = String(utf8: name)
        if EntryFlags.dependencyNames.contains(text) || text.hasSuffix(".noindex") {
            flags |= EntryFlags.dependency
        }
        if let dot = text.lastIndex(of: "."),
           EntryFlags.packageExtensions.contains(text[text.index(after: dot)...].lowercased()) {
            flags |= EntryFlags.package
        }
        return flags
    }

    /// 目录 `path`（标志 `flags`）的子项继承什么
    static func childInherited(flags: UInt8, path: String, home: String) -> UInt8 {
        var inherited = flags
        if flags & EntryFlags.package != 0 {
            inherited |= EntryFlags.insidePackage
        }
        if path == home {
            inherited |= EntryFlags.inHome
        }
        return inherited
    }

    /// 要不要进入这个目录
    private func descend(_ entry: DirectoryReader.Entry, name: [UInt8], flags: UInt8, parent: Task, id: UInt32) -> Task? {
        guard flags & EntryFlags.directory != 0, flags & EntryFlags.dataless == 0, devices.contains(entry.device)
        else { return nil }
        let isPackage = flags & EntryFlags.package != 0
        if isPackage, !options.indexPackageContents {
            return nil
        }
        let text = String(utf8: name)
        guard !options.excludedNames.contains(text) else { return nil }
        let path = parent.path == "/" ? "/" + text : parent.path + "/" + text
        guard !options.excludedPaths.contains(path) else { return nil }
        return Task(path: path, id: id, inherited: Self.childInherited(flags: flags, path: path, home: options.homePath))
    }

    private static func isDotEntry(_ name: UnsafeBufferPointer<UInt8>) -> Bool {
        name.isEmpty || (name.count <= 2 && name.allSatisfy { $0 == UInt8(ascii: ".") })
    }

    /// 名称统一成 NFC（APFS 保留创建时的形式，可能是 NFD）
    static func nfc(_ name: UnsafeBufferPointer<UInt8>) -> [UInt8] {
        guard name.contains(where: { $0 >= 0x80 }) else { return Array(name) }
        return Array(String(utf8: name).precomposedStringWithCanonicalMapping.utf8)
    }

    /// 大小压成 32 位：2 GB 以下精确到字节，以上按 KB（最高位做标记）
    static func encodeSize(_ size: UInt64) -> UInt32 {
        size < 0x8000_0000 ? UInt32(size) : 0x8000_0000 | UInt32(clamping: size >> 10)
    }

    static func decodeSize(_ value: UInt32) -> UInt64 {
        value & 0x8000_0000 == 0 ? UInt64(value) : UInt64(value & 0x7FFF_FFFF) << 10
    }
}

extension ScanChunk {
    mutating func append(id: UInt32, parent: UInt32, flags: UInt8, entry: DirectoryReader.Entry, name: [UInt8]) {
        ids.append(id)
        parents.append(parent)
        self.flags.append(flags)
        sizes.append(flags & EntryFlags.directory != 0 ? 0 : FileScanner.encodeSize(entry.size))
        mtimes.append(UInt32(clamping: entry.modified))
        nameLengths.append(UInt32(name.count))
        names.append(contentsOf: name)
    }
}

/// 每个线程写自己的格子，`concurrentPerform` 结束后才读
private final class ChunkSlots: @unchecked Sendable {
    private var chunks: [ScanChunk]
    private let lock = NSLock()

    init(count: Int) {
        chunks = Array(repeating: ScanChunk(), count: count)
    }

    subscript(index: Int) -> ScanChunk {
        get { lock.withLock { chunks[index] } }
        set { lock.withLock { chunks[index] = newValue } }
    }

    var all: [ScanChunk] {
        lock.withLock { chunks }
    }
}
