import Foundation

/// 截图历史的文件存储（ADR-0012）：`index.json` + 每条记录一个目录。
actor ScreenshotHistoryStore {
    static let thumbnailPixels = 480

    private let directory: URL
    private var index: ScreenshotIndex
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.directory = directory
        index = Self.loadIndex(in: directory)
    }

    var records: [ScreenshotRecord] {
        index.records
    }

    /// 要写入历史的文件
    struct Entry: Sendable {
        /// 不带标注的原图 PNG
        var original: Data
        /// 带标注的最终图 PNG（没有标注时为 nil）
        var rendered: Data?
        /// 标注对象 JSON（坐标相对截图左上角，单位 pt）
        var annotations: Data?
        var pixelWidth: Int
        var pixelHeight: Int
        var scale: CGFloat
    }

    /// 新增一条记录
    @discardableResult
    func add(_ entry: Entry, sourceApp: String?, date: Date) throws -> ScreenshotRecord {
        let id = UUID().uuidString
        let folder = directory.appending(path: id, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var bytes: Int64 = 0
        func write(_ data: Data, _ name: String) throws {
            try data.write(to: folder.appending(path: name), options: .atomic)
            bytes += Int64(data.count)
        }
        try write(entry.original, "original.png")
        if let rendered = entry.rendered {
            try write(rendered, "rendered.png")
        }
        if let annotations = entry.annotations {
            try write(annotations, "annotations.json")
        }
        // 缩略图用最终图
        if let thumbnail = ImageExporter.thumbnailPNG(fromPNG: entry.rendered ?? entry.original, maxPixel: Self.thumbnailPixels) {
            try write(thumbnail, "thumb.png")
        }
        var record = ScreenshotRecord(
            id: id, createdAt: date, pixelWidth: entry.pixelWidth, pixelHeight: entry.pixelHeight,
            sourceApp: sourceApp, ocrText: nil, bytes: bytes,
        )
        record.hasAnnotations = entry.annotations != nil
        record.scale = Double(entry.scale)
        index.records.insert(record, at: 0)
        try saveIndex()
        return record
    }

    func record(id: String) -> ScreenshotRecord? {
        index.records.first { $0.id == id }
    }

    /// 记录的目录
    func folder(for id: String) -> URL {
        directory.appending(path: id, directoryHint: .isDirectory)
    }

    /// 最终图（有标注时是 rendered.png，否则 original.png）
    func finalImageURL(for record: ScreenshotRecord) -> URL {
        folder(for: record.id).appending(path: record.hasAnnotations ? "rendered.png" : "original.png")
    }

    func originalURL(for id: String) -> URL {
        folder(for: id).appending(path: "original.png")
    }

    func thumbnailURL(for id: String) -> URL {
        folder(for: id).appending(path: "thumb.png")
    }

    /// 标注对象（坐标相对截图左上角，单位 pt）；没有标注时为空
    func annotations(for id: String) -> [Annotation] {
        guard let data = try? Data(contentsOf: folder(for: id).appending(path: "annotations.json")) else { return [] }
        return (try? JSONDecoder().decode([Annotation].self, from: data)) ?? []
    }

    /// 重新编辑标注后更新这条记录（原图不变），不新建记录（ADR-0012）
    func update(id: String, rendered: Data?, annotations: Data?) throws {
        guard let position = index.records.firstIndex(where: { $0.id == id }) else { return }
        let folder = folder(for: id)
        let manager = FileManager.default
        for (data, name) in [(rendered, "rendered.png"), (annotations, "annotations.json")] {
            let url = folder.appending(path: name)
            if let data {
                try data.write(to: url, options: .atomic)
            } else {
                try? manager.removeItem(at: url)
            }
        }
        let original = (try? Data(contentsOf: folder.appending(path: "original.png"))) ?? Data()
        if let thumbnail = ImageExporter.thumbnailPNG(fromPNG: rendered ?? original, maxPixel: Self.thumbnailPixels) {
            try thumbnail.write(to: folder.appending(path: "thumb.png"), options: .atomic)
        }
        index.records[position].hasAnnotations = annotations != nil
        index.records[position].bytes = Self.size(of: folder)
        try saveIndex()
    }

    func setPinned(_ pinned: Bool, id: String) throws {
        guard let position = index.records.firstIndex(where: { $0.id == id }) else { return }
        index.records[position].pinned = pinned
        try saveIndex()
    }

    func setOCRText(_ text: String, id: String) throws {
        guard let position = index.records.firstIndex(where: { $0.id == id }) else { return }
        index.records[position].ocrText = text
        try saveIndex()
    }

    func delete(_ ids: [String]) throws {
        guard !ids.isEmpty else { return }
        let removing = Set(ids)
        for id in removing {
            try? FileManager.default.removeItem(at: folder(for: id))
        }
        index.records.removeAll { removing.contains($0.id) }
        try saveIndex()
    }

    /// 超过上限时删除最旧的（收藏的不删）。返回删除的条数
    @discardableResult
    func enforce(limit: Int64?) throws -> Int {
        let ids = HistoryRetention.overLimit(index.records, limit: limit)
        try delete(ids)
        return ids.count
    }

    struct Stats: Sendable, Equatable {
        var count: Int
        var bytes: Int64
        var pinnedCount: Int
    }

    var stats: Stats {
        Stats(
            count: index.records.count,
            bytes: index.records.reduce(0) { $0 + $1.bytes },
            pinnedCount: index.records.count(where: \.pinned),
        )
    }

    private static func size(of folder: URL) -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    private func saveIndex() throws {
        try encoder.encode(index).write(to: directory.appending(path: "index.json"), options: .atomic)
    }

    /// 读取索引。文件损坏时改名保留，并从各条记录的目录重建（只能恢复基本信息）。
    private static func loadIndex(in directory: URL) -> ScreenshotIndex {
        let url = directory.appending(path: "index.json")
        guard let data = try? Data(contentsOf: url) else { return rebuild(in: directory) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let index = try? decoder.decode(ScreenshotIndex.self, from: data) {
            return index
        }
        let backup = directory.appending(path: "index.corrupt-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: url, to: backup)
        return rebuild(in: directory)
    }

    private static func rebuild(in directory: URL) -> ScreenshotIndex {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .creationDateKey]
        let folders = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        let records = folders.compactMap { folder -> ScreenshotRecord? in
            let original = folder.appending(path: "original.png")
            guard manager.fileExists(atPath: original.path) else { return nil }
            let size = (try? manager.attributesOfItem(atPath: original.path)[.size] as? Int64) ?? 0
            let created = (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            return ScreenshotRecord(
                id: folder.lastPathComponent, createdAt: created, pixelWidth: 0, pixelHeight: 0,
                sourceApp: nil, ocrText: nil, bytes: size,
            )
        }
        return ScreenshotIndex(records: records.sorted { $0.createdAt > $1.createdAt })
    }
}
