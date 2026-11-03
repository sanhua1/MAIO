import Foundation

/// 清理规则（纯函数）。固定的条目永远不会被清理。
enum RetentionPolicy {
    struct Entry: Sendable, Equatable {
        var id: Int64
        var byteSize: Int64
        var lastUsedAt: Date
        var isPinned: Bool
    }

    /// 总大小超过上限时，从最久没用过的开始删，直到不超过上限。limit 为 nil 表示永久保留。
    static func overLimit(_ entries: [Entry], limit: Int64?) -> [Int64] {
        guard let limit else { return [] }
        var total = entries.reduce(0) { $0 + $1.byteSize }
        guard total > limit else { return [] }
        var removed: [Int64] = []
        for entry in oldestFirst(entries) where total > limit {
            removed.append(entry.id)
            total -= entry.byteSize
        }
        return removed
    }

    /// 删除最旧的、合计至少 bytes 字节的条目。
    static func oldest(_ entries: [Entry], bytes: Int64) -> [Int64] {
        var freed: Int64 = 0
        var removed: [Int64] = []
        for entry in oldestFirst(entries) where freed < bytes {
            removed.append(entry.id)
            freed += entry.byteSize
        }
        return removed
    }

    /// 删除某个时间之前（最后使用时间早于 date）的条目。
    static func before(_ entries: [Entry], date: Date) -> [Int64] {
        entries.filter { !$0.isPinned && $0.lastUsedAt < date }.map(\.id)
    }

    private static func oldestFirst(_ entries: [Entry]) -> [Entry] {
        entries.filter { !$0.isPinned }.sorted { $0.lastUsedAt < $1.lastUsedAt }
    }
}

/// 存储上限选项。
enum StorageLimit: Int64, Codable, Sendable, CaseIterable {
    case mb500 = 500_000_000
    case gb1 = 1_000_000_000
    case gb2 = 2_000_000_000
    case gb5 = 5_000_000_000
    case gb10 = 10_000_000_000
    case gb20 = 20_000_000_000
    /// 永久保留（不按大小清理）
    case unlimited = 0

    var bytes: Int64? {
        self == .unlimited ? nil : rawValue
    }

    var title: String {
        self == .unlimited ? "永久保留" : ByteFormat.string(rawValue)
    }
}

enum ByteFormat {
    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .decimal)
    }
}
