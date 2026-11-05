import Foundation

/// 常用度：从启动器打开过的条目和当时的输入。
/// - 每个条目一个分数，每打开一次加 1，按时间衰减（一周减半）；
/// - 记下"输入了什么、选了哪一项"：以后同样的输入，这一项排第一。
struct UsageBook: Codable, Sendable, Equatable {
    struct Entry: Codable, Sendable, Equatable {
        var score: Double
        var updated: Date
    }

    static let halfLife: TimeInterval = 7 * 24 * 3600
    static let maxQueries = 400
    static let maxItems = 1000

    var items: [String: Entry] = [:]
    /// 输入（统一形式）→ 条目 ID → 次数
    var queries: [String: [String: Int]] = [:]

    mutating func record(_ id: String, query: String, at now: Date) {
        let current = usage(of: id, at: now)
        items[id] = Entry(score: current + 1, updated: now)
        let key = SearchKeys.normalize(query)
        if !key.isEmpty {
            queries[key, default: [:]][id, default: 0] += 1
        }
        prune(now: now)
    }

    /// 衰减到 `now` 的分数
    func usage(of id: String, at now: Date) -> Double {
        guard let entry = items[id] else { return 0 }
        let elapsed = max(0, now.timeIntervalSince(entry.updated))
        return entry.score * pow(0.5, elapsed / Self.halfLife)
    }

    /// 排序加分（和 `MatchScore` 的档次同一个量级）：
    /// 常用度最多 +30；这次的输入以前选过它 +25～40；以前输入过以它开头的内容并选了它 +10
    func bonus(for id: String, query: String, at now: Date) -> Int {
        var bonus = Int(min(30, 10 * log2(1 + usage(of: id, at: now))))
        let key = SearchKeys.normalize(query)
        guard !key.isEmpty else { return bonus }
        if let count = queries[key]?[id] {
            bonus += 20 + min(20, count * 5)
        } else if queries.contains(where: { $0.key.hasPrefix(key) && $0.value[id] != nil }) {
            bonus += 10
        }
        return bonus
    }

    /// 最近常用的条目 ID，按衰减后的分数从高到低
    func recent(limit: Int, at now: Date) -> [String] {
        items.keys
            .map { ($0, usage(of: $0, at: now)) }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    mutating func forget(_ id: String) {
        items[id] = nil
        for key in queries.keys {
            queries[key]?[id] = nil
            if queries[key]?.isEmpty == true {
                queries[key] = nil
            }
        }
    }

    /// 控制大小：分数衰减到很小的条目、多出来的输入记录删掉
    private mutating func prune(now: Date) {
        if items.count > Self.maxItems {
            let keep = Set(recent(limit: Self.maxItems, at: now))
            items = items.filter { keep.contains($0.key) }
        }
        if queries.count > Self.maxQueries {
            let ranked = queries.sorted { $0.value.values.reduce(0, +) > $1.value.values.reduce(0, +) }
            queries = Dictionary(uniqueKeysWithValues: ranked.prefix(Self.maxQueries).map { ($0.key, $0.value) })
        }
    }
}
