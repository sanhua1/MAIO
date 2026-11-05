import CoreServices
@testable import FeatureLauncher
import Foundation
import Testing

/// 在临时目录里造一棵文件树，测扫描、搜索、增量更新、存盘
struct FileIndexTests {
    let root: URL

    init() throws {
        // 用真实路径（/private/var/...，/var 是符号链接），和 FSEvents 报的路径一致
        let real = realpath(FileManager.default.temporaryDirectory.path(percentEncoded: false), nil)
        defer { free(real) }
        let base = URL(filePath: real.map { String(cString: $0) } ?? NSTemporaryDirectory(), directoryHint: .isDirectory)
        root = base.appending(path: "maio-index-\(UUID().uuidString)", directoryHint: .isDirectory)
        for path in [
            "docs/README.md",
            "docs/合同.txt",
            "src/app/main.swift",
            "src/app/Package.swift",
            "node_modules/x/index.js",
            ".hidden/a.txt",
        ] {
            try create(path)
        }
        try FileManager.default.createDirectory(at: root.appending(path: "Empty Folder"), withIntermediateDirectories: true)
    }

    private func create(_ relative: String, contents: String = "x") throws {
        let url = root.appending(path: relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    private var options: ScanOptions {
        ScanOptions(excludedPaths: [], excludedNames: [], threads: 2, homePath: root.path(percentEncoded: false))
    }

    /// 从 `/` 开始补上临时目录的父目录链，再扫描临时目录
    private func buildIndex() -> IndexData {
        var data = IndexData.root()
        let updater = IndexUpdater(options: options, devices: IndexConfiguration.devices())
        let event = FSEventsWatcher.Event(
            path: root.path(percentEncoded: false),
            flags: UInt32(kFSEventStreamEventFlagItemIsDir | kFSEventStreamEventFlagItemCreated), id: 1,
        )
        _ = updater.apply([event], to: &data)
        return data
    }

    private func names(_ data: IndexData, _ text: String, foldersOnly: Bool = false) -> [String] {
        guard let query = FileQuery(text, foldersOnly: foldersOnly) else { return [] }
        return data.search(query, limit: 50, now: 0).ids.map { data.name($0) }
    }

    @Test func `scans tree and finds by substring`() {
        let data = buildIndex()
        #expect(names(data, "readme") == ["README.md"])
        #expect(Set(names(data, "swift")) == ["main.swift", "Package.swift"])
        #expect(names(data, "main swift") == ["main.swift"])
        #expect(names(data, "zzz").isEmpty)
    }

    @Test func `pinyin initials and full`() {
        let data = buildIndex()
        #expect(names(data, "ht").contains("合同.txt"))
        #expect(names(data, "hetong") == ["合同.txt"])
        #expect(names(data, "合同") == ["合同.txt"])
    }

    @Test func `folders only and path terms`() {
        let data = buildIndex()
        #expect(names(data, "app", foldersOnly: true) == ["app"])
        #expect(names(data, "src/app/m") == ["main.swift"])
        #expect(names(data, "src/app/").isEmpty == false)
        #expect(names(data, "empty folder") == ["Empty Folder"])
    }

    @Test func `dependency and hidden rank lower`() throws {
        try create("index.js")
        let data = buildIndex()
        #expect(names(data, "index.js") == ["index.js", "index.js"])
        let first = try #require(FileQuery("index.js").map { data.search($0, limit: 5, now: 0).ids.first })
        #expect(data.path(first ?? 0).hasSuffix("/index.js") && !data.path(first ?? 0).contains("node_modules"))
    }

    @Test func `applies create delete and directory move`() throws {
        var data = buildIndex()
        let updater = IndexUpdater(options: options, devices: IndexConfiguration.devices())
        let created = root.appending(path: "docs/新报告.docx")
        try Data("x".utf8).write(to: created)
        _ = updater.apply([event(created, kFSEventStreamEventFlagItemCreated)], to: &data)
        #expect(names(data, "报告") == ["新报告.docx"])

        try FileManager.default.removeItem(at: created)
        _ = updater.apply([event(created, kFSEventStreamEventFlagItemRemoved)], to: &data)
        #expect(names(data, "报告").isEmpty)

        let old = root.appending(path: "src/app")
        let moved = root.appending(path: "moved-app")
        try FileManager.default.moveItem(at: old, to: moved)
        let flags = kFSEventStreamEventFlagItemRenamed | kFSEventStreamEventFlagItemIsDir
        _ = updater.apply([event(old, flags), event(moved, flags)], to: &data)
        let main = try #require(FileQuery("main.swift").flatMap { data.search($0, limit: 5, now: 0).ids.first })
        #expect(data.path(main).hasSuffix("/moved-app/main.swift"))
        #expect(data.find(path: old.path(percentEncoded: false)) == nil)
    }

    @Test func `persistence round trip after compaction`() throws {
        var data = buildIndex()
        let target = try #require(data.find(path: root.appending(path: "docs").path(percentEncoded: false)))
        data.markDeleted(subtreeOf: target)
        #expect(names(data, "readme").isEmpty)
        let file = root.appending(path: "index.bin")
        let header = IndexPersistence.Header(optionsHash: 42, lastEventID: 7, eventStoreUUID: "uuid", savedAt: 1)
        try IndexPersistence.save(data.compacted(), header: header, to: file)
        let loaded = try IndexPersistence.load(from: file)
        #expect(loaded.header == header)
        #expect(loaded.data.count == data.liveCount)
        #expect(names(loaded.data, "main") == ["main.swift"])
        #expect(loaded.data.find(path: root.appending(path: "src/app/main.swift").path(percentEncoded: false)) != nil)
    }

    @Test func `everything syntax on real tree`() throws {
        try create("docs/old/README.md")
        let data = buildIndex()
        #expect(Set(names(data, "readme|合同")) == ["README.md", "README.md", "合同.txt"])
        #expect(names(data, "readme !old/**") == ["README.md"])
        #expect(Set(names(data, "ext:swift")) == ["main.swift", "Package.swift"])
        #expect(names(data, "*.md") == ["README.md", "README.md"])
        #expect(names(data, "app/") == ["app"])
        #expect(names(data, "docs/old/") == ["old"])
        #expect(Set(names(data, "src/**/*.swift")) == ["main.swift", "Package.swift"])
        #expect(names(data, "parent:\(root.path(percentEncoded: false))/docs file:").count == 2)
        #expect(Set(names(data, "in:\(root.path(percentEncoded: false))/src ext:swift")) == ["main.swift", "Package.swift"])
        #expect(names(data, "folder: app") == ["app"])
        #expect(names(data, "size:empty").isEmpty)
        #expect(names(data, "dm:today readme").count == 2)
        #expect(names(data, "regex:^read.*\\.md$").count == 2)
        #expect(names(data, "ext:pdf").isEmpty)
    }

    @Test func `corrupt file is rejected`() throws {
        let file = root.appending(path: "bad.bin")
        try Data("MAIOIDX1garbage".utf8).write(to: file)
        #expect(throws: (any Error).self) { try IndexPersistence.load(from: file) }
    }

    private func event(_ url: URL, _ flags: Int) -> FSEventsWatcher.Event {
        FSEventsWatcher.Event(path: url.path(percentEncoded: false), flags: UInt32(flags), id: 2)
    }
}

struct FileQueryTests {
    @Test func `match quality tiers`() {
        func quality(_ name: String, _ term: String) -> Int {
            NameMatch.quality(Array(name.utf8)[...], Array(term.utf8))
        }
        #expect(quality("readme.md", "readme") == 4)
        #expect(quality("readme", "readme") == 4)
        #expect(quality("readme.old.md", "readme") == 3)
        #expect(quality("my-readme.md", "readme") == 2)
        #expect(quality("thereadme", "readme") == 1)
        #expect(quality("abc", "readme") == 0)
    }

    @Test func `primary term and pinyin detection`() {
        let query = FileQuery("ab longer")
        #expect(query?.primary == Array("longer".utf8))
        #expect(query?.primaryMayBePinyin == true)
        #expect(FileQuery("src/feature")?.primary == Array("feature".utf8))
        #expect(FileQuery("   ") == nil)
        #expect(FileQuery("a.txt")?.primaryMayBePinyin == false)
    }

    @Test func `size encoding round trip`() {
        #expect(FileScanner.decodeSize(FileScanner.encodeSize(123)) == 123)
        let big: UInt64 = 5 << 30
        #expect(FileScanner.decodeSize(FileScanner.encodeSize(big)) == big)
    }
}
