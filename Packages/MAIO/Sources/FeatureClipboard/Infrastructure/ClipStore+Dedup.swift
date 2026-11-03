import Foundation

/// 去重：最近 10 条内容相同（格式不同）的条目、终端"选中即复制"产生的同一次选择的多个版本。
extension ClipStore {
    /// 最近一条的元数据
    private struct Latest {
        var id: Int64
        var source: String?
        var created: Int64
        var pinned: Bool
    }

    /// 最近 recentDuplicateWindow 条里内容相同的条目
    func recentDuplicates(of contentKey: String?) throws -> [(id: Int64, pinned: Bool)] {
        guard let contentKey else { return [] }
        var result: [(id: Int64, pinned: Bool)] = []
        try database.query(
            """
            SELECT id, pinned FROM (SELECT id, pinned, content_key FROM clip ORDER BY last_used_at DESC LIMIT ?)
            WHERE content_key = ?
            """,
            [.int(Int64(Self.recentDuplicateWindow)), .text(contentKey)],
        ) { row in
            result.append((row.int(0), row.int(1) != 0))
        }
        return result
    }

    /// 最近一条是不是同一次选择的上一个版本（同一个 App、10 秒内、文字互相包含、没有固定）
    func selectionPredecessor(of payload: ClipPayload, source: String?, now: Date) throws -> Int64? {
        guard let source, let text = payload.plainText else { return nil }
        var candidate: Latest?
        try database.query("SELECT id, source, created_at, pinned FROM clip ORDER BY last_used_at DESC LIMIT 1") { row in
            candidate = Latest(id: row.int(0), source: row.text(1), created: row.int(2), pinned: row.int(3) != 0)
        }
        guard let candidate, candidate.source == source, !candidate.pinned,
              now.timeIntervalSince1970 - Double(candidate.created) / 1000 <= Self.selectionGrowthWindow,
              let old = try self.payload(candidate.id).plainText,
              ClipText.isSelectionGrowth(old: old, new: text) else { return nil }
        return candidate.id
    }
}
