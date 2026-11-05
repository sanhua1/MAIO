// 参考：references/oil-find/Sources/COilFind/coilfind.c（sift_entry_hash / sift_build_hash，MIT）
/// `(父目录, 小写名称) → 编号` 的开放寻址哈希表（只存编号，比较时回索引里读父目录和名称），每条约 6～8 字节。
/// 用于增量更新时按路径找到条目。已删除的条目留在表里，查找时跳过；存盘压缩后重建。
struct EntryLookup: Sendable {
    static let empty = UInt32.max

    var table: [UInt32] = []
    var used = 0

    /// 负载超过 0.6 就该扩容
    var needsGrowth: Bool {
        table.isEmpty || used * 5 >= table.count * 3
    }

    static func hash(parent: UInt32, name: ArraySlice<UInt8>) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        var value = parent
        for _ in 0 ..< 4 {
            hash = (hash ^ UInt64(value & 0xFF)) &* 0x0000_0100_0000_01B3
            value >>= 8
        }
        for byte in name {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    /// 起始槽位（乘法映射，避免取模）
    func slot(for hash: UInt64) -> Int {
        Int(UInt64(table.count).multipliedFullWidth(by: hash).high)
    }

    mutating func insert(_ id: UInt32, hash: UInt64) {
        var index = slot(for: hash)
        while table[index] != Self.empty {
            index = index + 1 == table.count ? 0 : index + 1
        }
        table[index] = id
        used += 1
    }
}

extension IndexData {
    /// 按父目录和名称（已经小写）找条目，跳过已删除的
    func find(parent: UInt32, foldedName name: ArraySlice<UInt8>) -> UInt32? {
        guard !lookup.table.isEmpty else { return nil }
        var index = lookup.slot(for: EntryLookup.hash(parent: parent, name: name))
        while true {
            let id = lookup.table[index]
            if id == EntryLookup.empty {
                return nil
            }
            if parents[Int(id)] == parent, isLive(id), foldedName(id) == name {
                return id
            }
            index = index + 1 == lookup.table.count ? 0 : index + 1
        }
    }

    /// 按完整路径找条目
    func find(path: String) -> UInt32? {
        var current: UInt32 = 0
        for component in path.split(separator: "/") {
            let name = IndexData.fold(Array(component.utf8))
            guard let next = find(parent: current, foldedName: name[...]) else { return nil }
            current = next
        }
        return current
    }

    mutating func insertLookup(_ id: UInt32) {
        if lookup.needsGrowth {
            rebuildLookup(capacity: max(1024, count * 2))
            return
        }
        lookup.insert(id, hash: EntryLookup.hash(parent: parents[Int(id)], name: foldedName(id)))
    }

    /// 重建整张表（扩容、压缩后）
    mutating func rebuildLookup(capacity: Int) {
        var size = 1024
        while size < capacity {
            size <<= 1
        }
        var fresh = EntryLookup()
        fresh.table = Array(repeating: EntryLookup.empty, count: size)
        for id in 1 ..< UInt32(count) where isLive(id) {
            fresh.insert(id, hash: EntryLookup.hash(parent: parents[Int(id)], name: foldedName(id)))
        }
        lookup = fresh
    }
}
