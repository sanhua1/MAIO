import CryptoKit
import Foundation

/// 剪贴板历史的持久化（ADR-0010）：SQLite 存元数据和小数据，大于 64 KB 的数据存成文件。
/// actor 保证所有数据库操作串行、且不在主线程执行。
actor ClipStore {
    static let inlineLimit = 64 * 1024
    /// 搜索文字最多保存这么多字符（超长文本只搜索开头部分）
    static let searchTextLimit = 200_000
    /// 新复制的内容和最近这么多条里的某条"内容相同"（格式不同也算）时，删掉旧的，新的排在最前
    static let recentDuplicateWindow = 10
    /// 同一个 App 在这么短时间内复制了包含关系的两段文字，视为同一次选择的延续，只保留最新的
    static let selectionGrowthWindow: TimeInterval = 10

    struct Stats: Sendable, Equatable {
        struct Bucket: Sendable, Equatable {
            var count = 0
            var bytes: Int64 = 0
        }

        var total = Bucket()
        var pinned = Bucket()
        var byKind: [ClipKind: Bucket] = [:]
        /// "2026-11" → 该月（按最后使用时间）
        var byMonth: [(month: String, bucket: Bucket)] = []
        var oldest: Date?

        static func == (lhs: Stats, rhs: Stats) -> Bool {
            lhs.total == rhs.total && lhs.byKind == rhs.byKind && lhs.oldest == rhs.oldest
        }
    }

    /// 扩展（ClipStore+Dedup.swift）也要用，所以不是 private
    let database: SQLiteDatabase
    private let blobs: URL

    init(directory: URL) throws {
        blobs = directory.appending(path: "blobs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        database = try SQLiteDatabase(path: directory.appending(path: "history.sqlite").path)
        try database.execute(Self.schema)
        // 旧数据库补列：content_key 为空的旧条目不参与"内容相同"的判断；ocr_text 为空表示还没识别（后台补）
        try Self.addColumn("content_key", to: database)
        try Self.addColumn("ocr_text", to: database)
    }

    private static let schema = """
    PRAGMA journal_mode = WAL;
    PRAGMA foreign_keys = ON;
    CREATE TABLE IF NOT EXISTS clip (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        hash TEXT NOT NULL UNIQUE,
        kind TEXT NOT NULL,
        summary TEXT NOT NULL,
        search_text TEXT NOT NULL,
        source TEXT,
        created_at INTEGER NOT NULL,
        last_used_at INTEGER NOT NULL,
        byte_size INTEGER NOT NULL,
        pinned INTEGER NOT NULL DEFAULT 0,
        thumbnail BLOB
    );
    CREATE INDEX IF NOT EXISTS clip_last_used ON clip(last_used_at);
    CREATE TABLE IF NOT EXISTS clip_data (
        clip_id INTEGER NOT NULL REFERENCES clip(id) ON DELETE CASCADE,
        item_index INTEGER NOT NULL,
        type TEXT NOT NULL,
        data BLOB,
        blob_name TEXT
    );
    CREATE INDEX IF NOT EXISTS clip_data_clip ON clip_data(clip_id);
    CREATE INDEX IF NOT EXISTS clip_data_blob ON clip_data(blob_name);
    """

    private static let itemColumns =
        "id, kind, summary, source, created_at, last_used_at, byte_size, pinned, thumbnail IS NOT NULL"

    // MARK: 写入

    /// 保存一次复制。内容完全相同的条目已存在时，只把它移到最前（更新最后使用时间和来源）。
    func insert(_ payload: ClipPayload, source: String?, now: Date = Date()) async throws -> ClipItem {
        // 缩略图可能要看原文件、解码大图：先做完再碰数据库，之后的操作全同步，和以前一样原子
        let newThumbnail = await makeThumbnail(for: payload)
        let hash = Self.hash(payload)
        var existing: Int64?
        try database.query("SELECT id FROM clip WHERE hash = ?", [.text(hash)]) { existing = $0.int(0) }
        let contentKey = payload.contentKey.map(Self.sha256)
        let recent = try recentDuplicates(of: contentKey)
        // 完全相同，或者最近有内容相同的固定条目：只把它移到最前
        if let keep = existing ?? recent.first(where: \.pinned)?.id {
            try database.query(
                "UPDATE clip SET last_used_at = ?, source = COALESCE(?, source) WHERE id = ?",
                [time(now), source.map { .text($0) } ?? .null, .int(keep)],
            )
            // 升级前保存的图片文件没有缩略图，再复制一次时补上
            if payload.kind == .files, try thumbnail(keep) == nil, let newThumbnail {
                try database.query("UPDATE clip SET thumbnail = ? WHERE id = ?", [.blob(newThumbnail), .int(keep)])
            }
            return try item(keep)
        }
        // 最近有内容相同（格式不同）的条目、或者是同一次选择的上一个版本：删掉旧的，保存新的
        let growth = try selectionPredecessor(of: payload, source: source, now: now)
        try delete(recent.map(\.id) + [growth].compactMap(\.self))
        let id = try database.transaction {
            try insertRow(
                payload,
                keys: .init(hash: hash, contentKey: contentKey),
                source: source,
                now: now,
                thumbnail: newThumbnail,
            )
        }
        return try item(id)
    }

    /// 去重用的两个哈希
    private struct RowKeys {
        let hash: String
        let contentKey: String?
    }

    private func insertRow(
        _ payload: ClipPayload,
        keys: RowKeys,
        source: String?,
        now: Date,
        thumbnail: Data?,
    ) throws -> Int64 {
        let searchText = Self.searchText(payload)
        try database.query(
            """
            INSERT INTO clip (hash, kind, summary, search_text, source, created_at, last_used_at, byte_size, thumbnail, content_key)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(keys.hash), .text(payload.kind.rawValue), .text(payload.summary), .text(searchText),
                source.map { .text($0) } ?? .null, time(now), time(now), .int(payload.byteSize),
                thumbnail.map { .blob($0) } ?? .null, keys.contentKey.map { .text($0) } ?? .null,
            ],
        )
        let id = database.lastInsertID
        for representation in payload.representations {
            var inline: SQLiteDatabase.Value = .blob(representation.data)
            var blobName: SQLiteDatabase.Value = .null
            if representation.data.count > Self.inlineLimit {
                let name = Self.sha256(representation.data)
                let url = blobs.appending(path: name)
                if !FileManager.default.fileExists(atPath: url.path) {
                    try representation.data.write(to: url, options: .atomic)
                }
                inline = .null
                blobName = .text(name)
            }
            try database.query(
                "INSERT INTO clip_data (clip_id, item_index, type, data, blob_name) VALUES (?, ?, ?, ?, ?)",
                [.int(id), .int(Int64(representation.itemIndex)), .text(representation.type), inline, blobName],
            )
        }
        return id
    }

    func touch(_ id: Int64, now: Date = Date()) throws {
        try database.query("UPDATE clip SET last_used_at = ? WHERE id = ?", [time(now), .int(id)])
    }

    func setPinned(_ id: Int64, _ pinned: Bool) throws {
        try database.query("UPDATE clip SET pinned = ? WHERE id = ?", [.int(pinned ? 1 : 0), .int(id)])
    }

    // MARK: 读取

    /// 列表数据。没有搜索词时返回最近 limit 条 + 全部固定条目；有搜索词时返回匹配的（每个词都要出现）。
    /// includeImageText：也搜图片里识别出的文字，命中时 `textInImage` 是命中处附近的一段
    func items(matching query: String, limit: Int, includeImageText: Bool = true) throws -> [ClipItem] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        var result: [ClipItem] = []
        if words.isEmpty {
            try database.query(
                "SELECT \(Self.itemColumns) FROM clip WHERE pinned = 0 ORDER BY last_used_at DESC LIMIT ?",
                [.int(Int64(limit))],
            ) { result.append(Self.item(from: $0)) }
            try database.query("SELECT \(Self.itemColumns) FROM clip WHERE pinned = 1") { result.append(Self.item(from: $0)) }
            return result
        }
        let haystack = includeImageText ? "search_text || char(10) || COALESCE(ocr_text, '')" : "search_text"
        let conditions = words.map { _ in "instr(\(haystack), ?) > 0" }.joined(separator: " AND ")
        try database.query(
            "SELECT \(Self.itemColumns), search_text, ocr_text FROM clip WHERE \(conditions) ORDER BY last_used_at DESC LIMIT ?",
            words.map { .text($0) } + [.int(Int64(limit))],
        ) { row in
            var item = Self.item(from: row)
            if includeImageText, let ocr = row.text(10), !ocr.isEmpty {
                item.textInImage = ClipText.imageTextSnippet(words: words, searchText: row.text(9) ?? "", ocrText: ocr)
            }
            result.append(item)
        }
        return result
    }

    func item(_ id: Int64) throws -> ClipItem {
        var found: ClipItem?
        try database.query("SELECT \(Self.itemColumns) FROM clip WHERE id = ?", [.int(id)]) { found = Self.item(from: $0) }
        guard let found else { throw SQLiteDatabase.Failure(message: "条目 \(id) 不存在") }
        return found
    }

    func payload(_ id: Int64) throws -> ClipPayload {
        var representations: [Representation] = []
        try database.query(
            "SELECT item_index, type, data, blob_name FROM clip_data WHERE clip_id = ? ORDER BY rowid",
            [.int(id)],
        ) { row in
            let data = try row.text(3).map { try Data(contentsOf: blobs.appending(path: $0)) } ?? row.blob(2) ?? Data()
            representations.append(Representation(itemIndex: Int(row.int(0)), type: row.text(1) ?? "", data: data))
        }
        return ClipPayload(representations: representations)
    }

    func thumbnail(_ id: Int64) throws -> Data? {
        var data: Data?
        try database.query("SELECT thumbnail FROM clip WHERE id = ?", [.int(id)]) { data = $0.blob(0) }
        return data
    }

    // MARK: 删除与统计

    func delete(_ ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        var names = Set<String>()
        try database.transaction {
            for id in ids {
                try database.query("SELECT blob_name FROM clip_data WHERE clip_id = ? AND blob_name IS NOT NULL", [.int(id)]) {
                    if let name = $0.text(0) {
                        names.insert(name)
                    }
                }
                try database.query("DELETE FROM clip WHERE id = ?", [.int(id)])
            }
        }
        // 其他条目不再引用的大文件才删除
        for name in names {
            var stillUsed = false
            try database.query("SELECT 1 FROM clip_data WHERE blob_name = ? LIMIT 1", [.text(name)]) { _ in stillUsed = true }
            if !stillUsed {
                try? FileManager.default.removeItem(at: blobs.appending(path: name))
            }
        }
    }

    func retentionEntries() throws -> [RetentionPolicy.Entry] {
        var entries: [RetentionPolicy.Entry] = []
        try database.query("SELECT id, byte_size, last_used_at, pinned FROM clip") { row in
            entries.append(RetentionPolicy.Entry(
                id: row.int(0), byteSize: row.int(1),
                lastUsedAt: Date(timeIntervalSince1970: Double(row.int(2)) / 1000), isPinned: row.int(3) != 0,
            ))
        }
        return entries
    }

    /// 按上限清理，返回删除的条数
    @discardableResult
    func enforce(limit: Int64?) throws -> Int {
        let ids = try RetentionPolicy.overLimit(retentionEntries(), limit: limit)
        try delete(ids)
        return ids.count
    }

    func stats() throws -> Stats {
        var stats = Stats()
        var months: [String: Stats.Bucket] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        try database.query("SELECT kind, byte_size, last_used_at, pinned FROM clip") { row in
            let bytes = row.int(1)
            let date = Date(timeIntervalSince1970: Double(row.int(2)) / 1000)
            let kind = ClipKind(rawValue: row.text(0) ?? "") ?? .text
            stats.total.count += 1
            stats.total.bytes += bytes
            stats.byKind[kind, default: .init()].count += 1
            stats.byKind[kind, default: .init()].bytes += bytes
            if row.int(3) != 0 {
                stats.pinned.count += 1
                stats.pinned.bytes += bytes
            }
            months[formatter.string(from: date), default: .init()].count += 1
            months[formatter.string(from: date), default: .init()].bytes += bytes
            stats.oldest = min(stats.oldest ?? date, date)
        }
        stats.byMonth = months.sorted { $0.key > $1.key }.map { (month: $0.key, bucket: $0.value) }
        return stats
    }
}

// MARK: 工具（放在扩展里，主体不超过 250 行）

extension ClipStore {

    static func addColumn(_ name: String, to database: SQLiteDatabase) throws {
        var exists = false
        try database.query("PRAGMA table_info(clip)") { row in
            if row.text(1) == name {
                exists = true
            }
        }
        guard !exists else { return }
        try database.execute("ALTER TABLE clip ADD COLUMN \(name) TEXT")
    }

    /// 时间存为毫秒整数，避免浮点比较的误差
    func time(_ date: Date) -> SQLiteDatabase.Value {
        .int(Int64((date.timeIntervalSince1970 * 1000).rounded()))
    }

    private static func item(from row: SQLiteDatabase.Row) -> ClipItem {
        ClipItem(
            id: row.int(0), kind: ClipKind(rawValue: row.text(1) ?? "") ?? .text, summary: row.text(2) ?? "",
            sourceBundleID: row.text(3), createdAt: Date(timeIntervalSince1970: Double(row.int(4)) / 1000),
            lastUsedAt: Date(timeIntervalSince1970: Double(row.int(5)) / 1000), byteSize: row.int(6),
            isPinned: row.int(7) != 0, hasThumbnail: row.int(8) != 0,
        )
    }

    static func searchText(_ payload: ClipPayload) -> String {
        var parts: [String] = []
        if let text = payload.plainText {
            parts.append(String(text.prefix(searchTextLimit)))
        }
        parts += payload.fileURLs.map(\.path)
        return parts.joined(separator: "\n").lowercased()
    }

    static func hash(_ payload: ClipPayload) -> String {
        var hasher = SHA256()
        for representation in payload.representations {
            hasher.update(data: Data("\(representation.itemIndex)|\(representation.type)|".utf8))
            hasher.update(data: representation.data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
