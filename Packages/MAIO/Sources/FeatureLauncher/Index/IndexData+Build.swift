import Foundation

extension IndexData {
    /// 把扫描结果按编号顺序追加进来。`firstID` 必须等于当前条数（扫描时就是从这里开始分配编号的）。
    mutating func append(_ chunks: [ScanChunk], firstID: UInt32, endID: UInt32) {
        precondition(Int(firstID) == count, "扫描编号必须接在索引末尾")
        let total = Int(endID - firstID)
        guard total > 0 else { return }
        // 每个编号在哪个线程的结果里、第几条、名称从哪里开始
        var chunkOf = [UInt16](repeating: 0, count: total)
        var indexOf = [UInt32](repeating: 0, count: total)
        var nameOffsetOf = [UInt32](repeating: 0, count: total)
        for (chunkIndex, chunk) in chunks.enumerated() {
            var offset: UInt32 = 0
            for (index, id) in chunk.ids.enumerated() {
                let slot = Int(id - firstID)
                chunkOf[slot] = UInt16(chunkIndex)
                indexOf[slot] = UInt32(index)
                nameOffsetOf[slot] = offset
                offset += chunk.nameLengths[index]
            }
        }
        reserve(total)
        let rebuild = lookup.table.count < (count + total) * 5 / 3
        for slot in 0 ..< total {
            let chunk = chunks[Int(chunkOf[slot])]
            let index = Int(indexOf[slot])
            let start = Int(nameOffsetOf[slot])
            let name = Array(chunk.names[start ..< start + Int(chunk.nameLengths[index])])
            appendEntry(
                parent: chunk.parents[index], flags: chunk.flags[index], size: chunk.sizes[index],
                mtime: chunk.mtimes[index], name: name, insertsLookup: !rebuild,
            )
        }
        if rebuild {
            rebuildLookup(capacity: count * 2)
        }
    }

    private mutating func reserve(_ extra: Int) {
        let target = count + extra
        parents.reserveCapacity(target)
        flags.reserveCapacity(target)
        depths.reserveCapacity(target)
        sizes.reserveCapacity(target)
        mtimes.reserveCapacity(target)
        nameStart.reserveCapacity(target + 1)
        rawStart.reserveCapacity(target)
        folded.reserveCapacity(folded.count + extra * 24)
    }
}
