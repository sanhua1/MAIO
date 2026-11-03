import Foundation

/// 截图历史的清理规则（和剪贴板 ADR-0010 的规则一致，各自实现，ADR-0012）。收藏的记录永远不清理。
enum HistoryRetention {
    /// 总大小超过上限时，从最旧的开始删，直到不超过上限。limit 为 nil 表示不限制
    static func overLimit(_ records: [ScreenshotRecord], limit: Int64?) -> [String] {
        guard let limit else { return [] }
        var total = records.reduce(0) { $0 + $1.bytes }
        guard total > limit else { return [] }
        var removed: [String] = []
        for record in oldestFirst(records) where total > limit {
            removed.append(record.id)
            total -= record.bytes
        }
        return removed
    }

    /// 删除最旧的、合计至少 bytes 字节的记录
    static func oldest(_ records: [ScreenshotRecord], bytes: Int64) -> [String] {
        var freed: Int64 = 0
        var removed: [String] = []
        for record in oldestFirst(records) where freed < bytes {
            removed.append(record.id)
            freed += record.bytes
        }
        return removed
    }

    static func before(_ records: [ScreenshotRecord], date: Date) -> [String] {
        records.filter { !$0.pinned && $0.createdAt < date }.map(\.id)
    }

    private static func oldestFirst(_ records: [ScreenshotRecord]) -> [ScreenshotRecord] {
        records.filter { !$0.pinned }.sorted { $0.createdAt < $1.createdAt }
    }
}

/// 截图历史的存储上限
enum HistoryLimit: Int64, Codable, Sendable, CaseIterable {
    case gb1 = 1_000_000_000
    case gb2 = 2_000_000_000
    case gb5 = 5_000_000_000
    case gb10 = 10_000_000_000
    case gb20 = 20_000_000_000
    case unlimited = 0

    var bytes: Int64? {
        self == .unlimited ? nil : rawValue
    }

    var title: String {
        self == .unlimited ? "不限制（永久保留）" : ByteCountFormatter.string(fromByteCount: rawValue, countStyle: .decimal)
    }
}

/// 历史面板：搜索和按日期分组
enum HistorySearch {
    struct DayGroup: Identifiable, Equatable {
        var day: Date
        var records: [ScreenshotRecord]

        var id: Date {
            day
        }
    }

    /// 按 OCR 文字、来源 App、日期（如 2026-11-03）搜索，不区分大小写
    static func filter(_ records: [ScreenshotRecord], query: String, calendar: Calendar = .current) -> [ScreenshotRecord] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return records }
        return records.filter { record in
            let parts = calendar.dateComponents([.year, .month, .day], from: record.createdAt)
            let date = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
            let haystack = [record.ocrText ?? "", record.sourceApp ?? "", date].joined(separator: "\n").lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    /// 按天分组，新的在前
    static func groupByDay(_ records: [ScreenshotRecord], calendar: Calendar = .current) -> [DayGroup] {
        let sorted = records.sorted { $0.createdAt > $1.createdAt }
        var groups: [DayGroup] = []
        for record in sorted {
            let day = calendar.startOfDay(for: record.createdAt)
            if groups.last?.day == day {
                groups[groups.count - 1].records.append(record)
            } else {
                groups.append(DayGroup(day: day, records: [record]))
            }
        }
        return groups
    }
}
