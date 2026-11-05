import Foundation

/// 一次文件搜索的结果
struct FileSearchResult: Sendable, Equatable {
    /// 排好序的前若干条
    var ids: [UInt32]
    /// 一共命中多少条
    var total: Int
}

extension IndexData {
    /// 搜索：先用名称块粗筛出候选（见 `QueryEvaluator`），逐条检查，打分取前 `limit` 条。
    /// 逐条检查是单线程的：试过分段并行，多个线程同时读同一批数组，引用计数的原子操作互相争抢，反而慢 10～20 倍。
    func search(_ query: FileQuery, limit: Int, now: UInt32) -> FileSearchResult {
        let evaluator = QueryEvaluator(data: self, query: query)
        var ranked = TopScores(limit: limit)
        var total = 0
        func consider(_ id: UInt32) {
            guard id != 0, flags[Int(id)] & EntryFlags.deleted == 0, evaluator.matches(id) else { return }
            total += 1
            ranked.insert(id, score: score(id, query, now: now))
        }
        if let candidates = evaluator.candidates() {
            candidates.forEach(consider)
        } else {
            (1 ..< UInt32(count)).forEach(consider)
        }
        return FileSearchResult(ids: ranked.sorted(), total: total)
    }

    func altKeysContain(_ id: UInt32, _ term: [UInt8]) -> Bool {
        var low = 0
        var high = altOwner.count
        while low < high {
            let middle = (low + high) / 2
            if altOwner[middle] < id {
                low = middle + 1
            } else {
                high = middle
            }
        }
        var index = low
        while index < altOwner.count, altOwner[index] == id {
            let key = altKeys[Int(altStart[index]) ..< Int(altStart[index + 1]) - 1]
            if ByteText.contains(key, term) {
                return true
            }
            index += 1
        }
        return false
    }

    /// 排序分数（参考 oil-find coilfind.c 的 sift_score_name_batch）：匹配质量为主，
    /// 用户目录、应用、文件夹、最近修改加分；依赖目录、包内部、隐藏、路径深扣分。
    func score(_ id: UInt32, _ query: FileQuery, now: UInt32) -> Int {
        let name = foldedName(id)
        let term = query.primary ?? []
        // 没有名称词（只有 ext:、dm: 这类条件）时按"包含"算，只比位置和标志
        var quality = term.isEmpty ? 1 : NameMatch.quality(name, term)
        if quality == 0, !term.isEmpty, altKeysContain(id, term) {
            quality = 2
        }
        var score = [0, 400, 600, 800, 1000][quality] - 2 * min(64, max(0, name.count - term.count))
        let entryFlags = flags[Int(id)]
        if entryFlags & EntryFlags.inHome != 0 {
            score += 60
        }
        if entryFlags & EntryFlags.package != 0, name.hasSuffix(".app".utf8) {
            score += 150
        }
        if entryFlags & EntryFlags.directory != 0 {
            score += 20
        }
        score += Self.recencyBonus(age: now &- min(now, mtimes[Int(id)]))
        if entryFlags & EntryFlags.dependency != 0 {
            score -= 350
        }
        if entryFlags & EntryFlags.insidePackage != 0 {
            score -= 300
        }
        if entryFlags & EntryFlags.hidden != 0 {
            score -= 200
        }
        return score - 5 * min(16, Int(depths[Int(id)]))
    }

    private static func recencyBonus(age: UInt32) -> Int {
        switch age {
        case ...86400: 60
        case ...604_800: 45
        case ...2_592_000: 30
        case ...31_536_000: 10
        default: 0
        }
    }
}

private extension ArraySlice<UInt8> {
    func hasSuffix(_ suffix: String.UTF8View) -> Bool {
        count >= suffix.count && self.suffix(suffix.count).elementsEqual(suffix)
    }
}

/// 只保留分数最高的 `limit` 条（小顶堆）
struct TopScores {
    let limit: Int
    private var entries: [(score: Int, id: UInt32)] = []

    init(limit: Int) {
        self.limit = limit
        entries.reserveCapacity(limit)
    }

    mutating func insert(_ id: UInt32, score: Int) {
        if entries.count < limit {
            entries.append((score, id))
            siftUp(entries.count - 1)
        } else if let lowest = entries.first, score > lowest.score {
            entries[0] = (score, id)
            siftDown(0)
        }
    }

    /// 分数从高到低；同分时编号小的在前（更早扫到，通常路径更浅）
    func sorted() -> [UInt32] {
        entries.sorted { $0.score != $1.score ? $0.score > $1.score : $0.id < $1.id }.map(\.id)
    }

    private mutating func siftUp(_ start: Int) {
        var child = start
        while child > 0 {
            let parent = (child - 1) / 2
            guard entries[child].score < entries[parent].score else { return }
            entries.swapAt(child, parent)
            child = parent
        }
    }

    private mutating func siftDown(_ start: Int) {
        var parent = start
        while true {
            let left = parent * 2 + 1
            let right = left + 1
            var smallest = parent
            if left < entries.count, entries[left].score < entries[smallest].score {
                smallest = left
            }
            if right < entries.count, entries[right].score < entries[smallest].score {
                smallest = right
            }
            guard smallest != parent else { return }
            entries.swapAt(parent, smallest)
            parent = smallest
        }
    }
}
