extension IndexData {
    /// 去掉打了删除标记的条目，重新编号（父目录的编号仍然小于子项：删除总是整棵子树一起删，活着的条目父目录也活着）
    func compacted() -> IndexData {
        guard deletedCount > 0 else { return self }
        var result = IndexData()
        result.altKeyMaker = altKeyMaker
        var newID = [UInt32](repeating: UInt32.max, count: count)
        for id in 0 ..< UInt32(count) where isLive(id) {
            let parent = id == 0 ? 0 : newID[Int(parents[Int(id)])]
            guard parent != UInt32.max else { continue }
            newID[Int(id)] = result.appendEntry(
                parent: parent, flags: flags[Int(id)], size: sizes[Int(id)], mtime: mtimes[Int(id)],
                name: rawName(id), insertsLookup: false,
            )
        }
        result.rebuildLookup(capacity: result.count * 2)
        return result
    }

    /// 原名的字节（没有单独存原名时就是小写名）
    func rawName(_ id: UInt32) -> [UInt8] {
        let start = rawStart[Int(id)]
        guard start != Self.sameAsFolded else { return Array(foldedName(id)) }
        let end = raw[Int(start)...].firstIndex(of: 0) ?? raw.endIndex
        return Array(raw[Int(start) ..< end])
    }

    /// 给 `id` 和它的所有子孙打删除标记（利用父目录编号更小：从 `id` 往后扫一遍即可）
    mutating func markDeleted(subtreeOf id: UInt32, includingSelf: Bool = true) {
        markDeleted(roots: [id], includingSelf: includingSelf)
    }

    /// 一次删除多棵子树（只扫一遍）
    mutating func markDeleted(roots: [UInt32], includingSelf: Bool) {
        guard let first = roots.min() else { return }
        // 不删自己时，直接子项靠"父目录在 roots 里"判断；更深的靠"父目录已删除"
        let keptRoots = includingSelf ? Set<UInt32>() : Set(roots)
        for root in roots where includingSelf && isLive(root) && root != 0 {
            flags[Int(root)] |= EntryFlags.deleted
            deletedCount += 1
        }
        for id in (first + 1) ..< UInt32(count) where isLive(id) {
            let parent = parents[Int(id)]
            if keptRoots.contains(parent) || !isLive(parent) {
                flags[Int(id)] |= EntryFlags.deleted
                deletedCount += 1
            }
        }
    }
}
