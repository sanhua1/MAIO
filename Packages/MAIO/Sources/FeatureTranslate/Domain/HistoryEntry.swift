import Foundation

/// 一条翻译历史：原文 + 各翻译源的译文。
struct HistoryEntry: Codable, Sendable, Equatable, Identifiable {
    struct Item: Codable, Sendable, Equatable, Hashable {
        var service: String
        var text: String
    }

    var id = UUID()
    var date: Date
    var text: String
    var source: Language
    var target: Language
    var results: [Item]

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return text.localizedCaseInsensitiveContains(query)
            || results.contains { $0.text.localizedCaseInsensitiveContains(query) }
    }
}

/// 历史记录列表的纯逻辑：新的在前，同样的原文只保留最新一条，超过上限丢弃最旧的。
enum HistoryList {
    static func adding(_ entry: HistoryEntry, to entries: [HistoryEntry], limit: Int) -> [HistoryEntry] {
        var result = entries.filter { $0.text != entry.text || $0.target != entry.target }
        result.insert(entry, at: 0)
        return Array(result.prefix(max(1, limit)))
    }
}
