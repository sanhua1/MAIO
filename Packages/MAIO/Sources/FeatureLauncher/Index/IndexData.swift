import Foundation

// 参考：references/oil-find/docs/ARCHITECTURE.md（SoA 布局、parent < child，MIT，Copyright (c) 2026 Lin Zhihuang）
/// 文件索引的全部数据。每个字段一个数组（按编号排列），名称首尾相接存成一大块，搜索时直接扫这块内存。
///
/// 不变量（增量更新、搜索、存盘都依赖）：
/// - 编号 0 是根目录 `/`；**父目录的编号小于子项**；
/// - `nameStart` 单调递增，第 i 条的名称是 `folded[nameStart[i] ..< nameStart[i+1]-1]`（每个名称后面跟一个 0）；
/// - 删除只打 `deleted` 标记，名称留在原处，存盘时 `compacted()` 才真正去掉。
struct IndexData: Sendable {
    static let sameAsFolded = UInt32.max

    var parents: [UInt32] = []
    var flags: [UInt8] = []
    var depths: [UInt8] = []
    /// `FileScanner.encodeSize` 压缩过的大小
    var sizes: [UInt32] = []
    /// 修改时间（秒）
    var mtimes: [UInt32] = []
    /// 小写 + NFC 的名称（搜索用），每个后面跟 0
    var folded: [UInt8] = []
    /// 每条在 `folded` 里的起点；比条数多一个（最后一个是结尾）
    var nameStart: [UInt32] = [0]
    /// 原名和小写名不同时，原名在 `raw` 里的起点；相同时是 `sameAsFolded`
    var rawStart: [UInt32] = []
    var raw: [UInt8] = []
    /// 拼音等备用搜索键：`altKeys` 首尾相接（每个后面跟 0），第 k 个属于 `altOwner[k]`
    var altKeys: [UInt8] = []
    var altStart: [UInt32] = [0]
    var altOwner: [UInt32] = []
    /// `(父目录, 小写名称) → 编号`
    var lookup = EntryLookup()
    /// 已打删除标记的条数
    var deletedCount = 0
    /// 生成拼音键（带汉字读音缓存）
    var altKeyMaker = AltKeys()

    var count: Int {
        parents.count
    }

    var liveCount: Int {
        count - deletedCount
    }

    /// 只有根目录 `/` 的空索引
    static func root() -> IndexData {
        var data = IndexData()
        data.appendEntry(parent: 0, flags: EntryFlags.directory, size: 0, mtime: 0, name: [])
        return data
    }

    // MARK: 读取

    func foldedName(_ id: UInt32) -> ArraySlice<UInt8> {
        let start = Int(nameStart[Int(id)])
        return folded[start ..< Int(nameStart[Int(id) + 1]) - 1]
    }

    /// 显示用的原名
    func name(_ id: UInt32) -> String {
        let start = rawStart[Int(id)]
        guard start != Self.sameAsFolded else { return String(utf8: foldedName(id)) }
        let end = raw[Int(start)...].firstIndex(of: 0) ?? raw.endIndex
        return String(utf8: raw[Int(start) ..< end])
    }

    /// 沿父目录拼出完整路径
    func path(_ id: UInt32) -> String {
        var parts: [String] = []
        var current = id
        while current != 0 {
            parts.append(name(current))
            current = parents[Int(current)]
        }
        return "/" + parts.reversed().joined(separator: "/")
    }

    /// 小写的完整路径（路径条件用）
    func foldedPath(_ id: UInt32) -> [UInt8] {
        var parts: [ArraySlice<UInt8>] = []
        var current = id
        while current != 0 {
            parts.append(foldedName(current))
            current = parents[Int(current)]
        }
        var result: [UInt8] = []
        for part in parts.reversed() {
            result.append(UInt8(ascii: "/"))
            result.append(contentsOf: part)
        }
        return result.isEmpty ? [UInt8(ascii: "/")] : result
    }

    func isLive(_ id: UInt32) -> Bool {
        flags[Int(id)] & EntryFlags.deleted == 0
    }

    // MARK: 写入

    /// 追加一条，返回编号。父目录必须已经存在（编号更小）。
    /// `insertsLookup` 为 false 时不登记哈希表（批量建索引时最后一次性重建）
    @discardableResult
    mutating func appendEntry(
        parent: UInt32, flags entryFlags: UInt8, size: UInt32, mtime: UInt32, name: [UInt8], insertsLookup: Bool = true,
    ) -> UInt32 {
        let id = UInt32(count)
        parents.append(parent)
        flags.append(entryFlags)
        depths.append(id == 0 ? 0 : depths[Int(parent)] &+ 1)
        sizes.append(size)
        mtimes.append(mtime)
        let lower = Self.fold(name)
        folded.append(contentsOf: lower)
        folded.append(0)
        nameStart.append(UInt32(folded.count))
        if lower == name {
            rawStart.append(Self.sameAsFolded)
        } else {
            rawStart.append(UInt32(raw.count))
            raw.append(contentsOf: name)
            raw.append(0)
        }
        appendAltKeys(id: id, name: name)
        if id != 0, insertsLookup {
            insertLookup(id)
        }
        return id
    }

    private mutating func appendAltKeys(id: UInt32, name: [UInt8]) {
        guard name.contains(where: { $0 >= 0x80 }) else { return }
        for key in altKeyMaker.keys(for: String(utf8: name)) {
            altKeys.append(contentsOf: key)
            altKeys.append(0)
            altStart.append(UInt32(altKeys.count))
            altOwner.append(id)
        }
    }

    /// 小写：ASCII 直接改字节；含非 ASCII 时用 Unicode 规则（É → é）
    static func fold(_ name: [UInt8]) -> [UInt8] {
        if name.allSatisfy({ $0 < 0x80 }) {
            return name.map { $0 &- 65 < 26 ? $0 | 0x20 : $0 }
        }
        return Array(String(utf8: name).lowercased().precomposedStringWithCanonicalMapping.utf8)
    }
}
