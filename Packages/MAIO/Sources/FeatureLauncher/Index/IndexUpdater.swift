import Darwin
import Foundation

// 参考：references/oil-find/Sources/OilFindCore/IndexUpdater.swift、references/cardinal/search-cache/src/cache.rs（MIT）
/// 把一批 FSEvents 事件应用到索引上。每条事件都重新 lstat 这个路径，按"现在磁盘上是什么样"更新：
/// 不存在 → 删掉（连同子树）；新出现 → 补上父目录链再加进来（目录要扫一遍里面）；已存在 → 更新大小和时间。
struct IndexUpdater {
    let options: ScanOptions
    let devices: Set<Int32>

    enum Outcome {
        case applied(changed: Bool)
        /// 根路径丢了事件、事件编号回绕：只能整盘重扫
        case needsFullRescan
    }

    /// `/System/Volumes/Data/Users/...` 和 `/Users/...` 是同一个位置（firmlink），统一成后者
    static func normalize(_ path: String) -> String {
        let data = "/System/Volumes/Data"
        if path == data {
            return "/"
        }
        return path.hasPrefix(data + "/") ? String(path.dropFirst(data.count)) : path
    }

    func apply(_ events: [FSEventsWatcher.Event], to data: inout IndexData) -> Outcome {
        var merged: [String: FSEventsWatcher.Event] = [:]
        for event in events where !event.isHistoryDone {
            if event.requiresFullRescan || (event.mustRescanSubtree && Self.normalize(event.path).count <= 1) {
                return .needsFullRescan
            }
            let path = Self.normalize(event.path)
            merged[path, default: FSEventsWatcher.Event(path: path, flags: 0, id: event.id)].flags |= event.flags
        }
        // 最小祖先：要整棵重读的目录下面的其他事件不用单独处理（参考 Cardinal cache.rs 996-1043）
        let rescans = merged.values.filter { $0.mustRescanSubtree || $0.directoryAppeared }.map(\.path)
        var deletions: [UInt32] = []
        var changed = false
        for path in merged.keys.sorted() where indexable(path) {
            if rescans.contains(where: { path.hasPrefix($0 + "/") }) {
                continue
            }
            guard let event = merged[path] else { continue }
            changed = update(path, event: event, data: &data, deletions: &deletions) || changed
        }
        if !deletions.isEmpty {
            data.markDeleted(roots: deletions, includingSelf: true)
        }
        return .applied(changed: changed)
    }

    private func update(_ path: String, event: FSEventsWatcher.Event, data: inout IndexData, deletions: inout [UInt32]) -> Bool {
        let existing = data.find(path: path)
        var info = stat()
        guard lstat(path, &info) == 0 else {
            if let existing {
                deletions.append(existing)
            }
            return existing != nil
        }
        let isDirectory = info.st_mode & S_IFMT == S_IFDIR
        if let existing {
            let wasDirectory = data.flags[Int(existing)] & EntryFlags.directory != 0
            guard wasDirectory == isDirectory else {
                data.markDeleted(subtreeOf: existing)
                return add(path, info: info, data: &data) != nil
            }
            data.sizes[Int(existing)] = isDirectory ? 0 : FileScanner.encodeSize(UInt64(max(0, info.st_size)))
            data.mtimes[Int(existing)] = UInt32(clamping: info.st_mtimespec.tv_sec)
            if isDirectory, event.mustRescanSubtree || event.directoryAppeared {
                rescanChildren(of: existing, path: path, data: &data)
            }
            return true
        }
        return add(path, info: info, data: &data) != nil
    }

    /// 加一条（父目录不在索引里就先补上）；目录会扫一遍里面
    @discardableResult
    private func add(_ path: String, info: stat, data: inout IndexData) -> UInt32? {
        let parentPath = (path as NSString).deletingLastPathComponent
        guard let parent = ensureDirectory(parentPath, data: &data) else { return nil }
        let name = Array((path as NSString).lastPathComponent.precomposedStringWithCanonicalMapping.utf8)
        let isDirectory = info.st_mode & S_IFMT == S_IFDIR
        let inherited = FileScanner.childInherited(flags: data.flags[Int(parent)], path: parentPath, home: options.homePath)
        let flags = FileScanner.entryFlags(isDirectory: isDirectory, name: name, bsdFlags: info.st_flags, inherited: inherited)
        let id = data.appendEntry(
            parent: parent, flags: flags, size: isDirectory ? 0 : FileScanner.encodeSize(UInt64(max(0, info.st_size))),
            mtime: UInt32(clamping: info.st_mtimespec.tv_sec), name: name,
        )
        if isDirectory {
            rescanChildren(of: id, path: path, data: &data)
        }
        return id
    }

    private func ensureDirectory(_ path: String, data: inout IndexData) -> UInt32? {
        if path == "/" {
            return 0
        }
        if let id = data.find(path: path) {
            return id
        }
        var info = stat()
        guard indexable(path), lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return nil }
        // 补父目录时不扫里面（里面的东西会有自己的事件，或者由调用方扫）
        let parentPath = (path as NSString).deletingLastPathComponent
        guard let parent = ensureDirectory(parentPath, data: &data) else { return nil }
        let name = Array((path as NSString).lastPathComponent.precomposedStringWithCanonicalMapping.utf8)
        let inherited = FileScanner.childInherited(flags: data.flags[Int(parent)], path: parentPath, home: options.homePath)
        let flags = FileScanner.entryFlags(isDirectory: true, name: name, bsdFlags: info.st_flags, inherited: inherited)
        return data.appendEntry(
            parent: parent,
            flags: flags,
            size: 0,
            mtime: UInt32(clamping: info.st_mtimespec.tv_sec),
            name: name,
        )
    }

    /// 删掉目录下原有的内容，重新扫一遍
    func rescanChildren(of id: UInt32, path: String, data: inout IndexData) {
        let flags = data.flags[Int(id)]
        guard flags & EntryFlags.dataless == 0, options.indexPackageContents || flags & EntryFlags.package == 0 else { return }
        data.markDeleted(subtreeOf: id, includingSelf: false)
        var small = options
        small.threads = 2
        let scanner = FileScanner(options: small, devices: devices)
        let inherited = FileScanner.childInherited(flags: flags, path: path, home: options.homePath)
        guard let result = scanner.scan(path, id: id, inherited: inherited, firstID: UInt32(data.count)) else { return }
        data.append(result.chunks, firstID: UInt32(data.count), endID: result.nextID)
    }

    /// 路径在不在索引范围里：不在排除目录下、不含排除的名称、（默认）不在包里面
    func indexable(_ path: String) -> Bool {
        if options.excludedPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return false
        }
        let components = path.split(separator: "/")
        for (index, component) in components.enumerated() {
            if options.excludedNames.contains(String(component)) {
                return false
            }
            let isAncestor = index < components.count - 1
            if isAncestor, !options.indexPackageContents, let dot = component.lastIndex(of: "."),
               EntryFlags.packageExtensions.contains(component[component.index(after: dot)...].lowercased()) {
                return false
            }
        }
        return true
    }
}
