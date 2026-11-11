import CoreGraphics
@testable import FeatureClipboard
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

struct ClipStoreTests {
    private func makeStore() throws -> (ClipStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "maio-clip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try (ClipStore(directory: directory), directory)
    }

    @Test func `inserts and deduplicates`() async throws {
        let (store, _) = try makeStore()
        let first = try await store.insert(text("hello"), source: "com.a", now: Date(timeIntervalSince1970: 100))
        _ = try await store.insert(text("world"), source: "com.b", now: Date(timeIntervalSince1970: 200))
        let again = try await store.insert(text("hello"), source: "com.c", now: Date(timeIntervalSince1970: 300))
        #expect(again.id == first.id)
        #expect(again.sourceBundleID == "com.c")
        let items = try await store.items(matching: "", limit: 10)
        #expect(items.count == 2)
        #expect(try await store.payload(first.id) == text("hello"))
    }

    private func rich(_ value: String, html: String) -> ClipPayload {
        ClipPayload(representations: [
            Representation(itemIndex: 0, type: PasteType.plainText, data: Data(value.utf8)),
            Representation(itemIndex: 0, type: PasteType.html, data: Data(html.utf8)),
        ])
    }

    @Test func `same text with different formatting within recent ten moves to top`() async throws {
        let (store, _) = try makeStore()
        let first = try await store.insert(
            rich("hello", html: "<b>hello</b>"),
            source: "com.a",
            now: Date(timeIntervalSince1970: 1),
        )
        _ = try await store.insert(text("other"), source: nil, now: Date(timeIntervalSince1970: 2))
        let again = try await store.insert(text("hello"), source: "com.b", now: Date(timeIntervalSince1970: 3))
        #expect(again.id != first.id)
        let items = try await store.items(matching: "", limit: 10)
        #expect(items.map(\.summary) == ["hello", "other"])
        // 新的那份内容留下（纯文本），旧的带格式的删掉
        #expect(try await store.payload(again.id) == text("hello"))
    }

    @Test func `duplicates older than recent ten are kept`() async throws {
        let (store, _) = try makeStore()
        _ = try await store.insert(rich("hello", html: "<i>hello</i>"), source: nil, now: Date(timeIntervalSince1970: 0))
        for index in 1 ... ClipStore.recentDuplicateWindow {
            _ = try await store.insert(text("item \(index)"), source: nil, now: Date(timeIntervalSince1970: Double(index)))
        }
        _ = try await store.insert(text("hello"), source: nil, now: Date(timeIntervalSince1970: 100))
        let items = try await store.items(matching: "hello", limit: 20)
        #expect(items.count == 2)
    }

    @Test func `pinned duplicate is moved to top instead of replaced`() async throws {
        let (store, _) = try makeStore()
        let pinned = try await store.insert(rich("hello", html: "<u>hello</u>"), source: nil, now: Date(timeIntervalSince1970: 1))
        try await store.setPinned(pinned.id, true)
        let again = try await store.insert(text("hello"), source: nil, now: Date(timeIntervalSince1970: 2))
        #expect(again.id == pinned.id)
        #expect(again.isPinned)
    }

    @Test func `terminal selection growth keeps only the latest`() async throws {
        let (store, _) = try makeStore()
        _ = try await store.insert(text("\n\nrecap: hello"), source: "term", now: Date(timeIntervalSince1970: 1))
        _ = try await store.insert(text("\r\n\r\nrecap: hello world"), source: "term", now: Date(timeIntervalSince1970: 2))
        let last = try await store.insert(text("recap: hello world, again "), source: "term", now: Date(timeIntervalSince1970: 3))
        let items = try await store.items(matching: "", limit: 10)
        #expect(items.map(\.id) == [last.id])
    }

    @Test func `growth needs same app and short interval`() async throws {
        let (store, _) = try makeStore()
        _ = try await store.insert(text("hello"), source: "a", now: Date(timeIntervalSince1970: 1))
        _ = try await store.insert(text("hello world"), source: "b", now: Date(timeIntervalSince1970: 2))
        _ = try await store.insert(text("hello world!"), source: "b", now: Date(timeIntervalSince1970: 100))
        #expect(try await store.items(matching: "", limit: 10).count == 3)
    }

    @Test func `line endings and surrounding spaces count as same content`() async throws {
        let (store, _) = try makeStore()
        _ = try await store.insert(text("a\r\nb "), source: "x", now: Date(timeIntervalSince1970: 1))
        _ = try await store.insert(text("other"), source: "y", now: Date(timeIntervalSince1970: 2))
        _ = try await store.insert(text("\na\nb"), source: "z", now: Date(timeIntervalSince1970: 3))
        #expect(try await store.items(matching: "", limit: 10).count == 2)
    }

    @Test func `searches chinese and multiple words`() async throws {
        let (store, _) = try makeStore()
        _ = try await store.insert(text("今天天气很好 Hello World"), source: nil)
        _ = try await store.insert(text("明天下雨"), source: nil)
        #expect(try await store.items(matching: "天气", limit: 10).count == 1)
        #expect(try await store.items(matching: "天", limit: 10).count == 2)
        #expect(try await store.items(matching: "hello 天气", limit: 10).count == 1)
        #expect(try await store.items(matching: "WORLD 下雨", limit: 10).isEmpty)
    }

    @Test func `large data goes to blob and is removed on delete`() async throws {
        let (store, directory) = try makeStore()
        let big = Data(repeating: 7, count: ClipStore.inlineLimit + 1)
        let payload = ClipPayload(representations: [Representation(itemIndex: 0, type: PasteType.png, data: big)])
        let item = try await store.insert(payload, source: nil)
        let blobs = directory.appending(path: "blobs")
        #expect(try FileManager.default.contentsOfDirectory(atPath: blobs.path).count == 1)
        #expect(try await store.payload(item.id) == payload)
        try await store.delete([item.id])
        #expect(try FileManager.default.contentsOfDirectory(atPath: blobs.path).isEmpty)
    }

    @Test func `pinned survives enforce and stats add up`() async throws {
        let (store, _) = try makeStore()
        let old = try await store.insert(
            text(String(repeating: "a", count: 100)),
            source: nil,
            now: Date(timeIntervalSince1970: 1),
        )
        let pinned = try await store.insert(
            text(String(repeating: "b", count: 100)),
            source: nil,
            now: Date(timeIntervalSince1970: 2),
        )
        _ = try await store.insert(text(String(repeating: "c", count: 100)), source: nil, now: Date(timeIntervalSince1970: 3))
        try await store.setPinned(pinned.id, true)
        let removed = try await store.enforce(limit: 250)
        #expect(removed == 1)
        let ids = try await store.items(matching: "", limit: 10).map(\.id)
        #expect(!ids.contains(old.id))
        #expect(ids.contains(pinned.id))
        let stats = try await store.stats()
        #expect(stats.total.count == 2)
        #expect(stats.total.bytes == 200)
        #expect(stats.pinned.count == 1)
    }

    // MARK: 图片文件预览

    private func filePayload(_ url: URL) -> ClipPayload {
        ClipPayload(representations: [Representation(itemIndex: 0, type: PasteType.fileURL, data: Data(url.absoluteString.utf8))])
    }

    private func pngData() throws -> Data {
        guard let context = CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ), let image = context.makeImage() else { throw CocoaError(.fileReadCorruptFile) }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileReadCorruptFile) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileReadCorruptFile) }
        return output as Data
    }

    @Test func `image file gets a thumbnail and preview`() async throws {
        let (store, directory) = try makeStore()
        let file = directory.appending(path: "red.png")
        try pngData().write(to: file)
        let item = try await store.insert(filePayload(file), source: "com.apple.finder")
        #expect(item.kind == .files)
        #expect(item.hasThumbnail)
        #expect(try await store.thumbnail(item.id) != nil)
        #expect(try await store.items(matching: "", limit: 10).first?.hasThumbnail == true)
        let payload = try await store.payload(item.id)
        let preview = try #require(await store.previewImage(for: item, payload: payload))
        #expect(preview.pixelSize == CGSize(width: 8, height: 8))
    }

    @Test func `text and missing files get no thumbnail`() async throws {
        let (store, directory) = try makeStore()
        let textFile = directory.appending(path: "notes.txt")
        try Data("hello".utf8).write(to: textFile)
        let text = try await store.insert(filePayload(textFile), source: nil)
        #expect(!text.hasThumbnail)
        let missing = try await store.insert(filePayload(directory.appending(path: "gone.png")), source: nil)
        #expect(!missing.hasThumbnail)
        #expect(try await store.thumbnail(missing.id) == nil)
    }

    @Test func `preview falls back to archived thumbnail after file moves away`() async throws {
        let (store, directory) = try makeStore()
        let file = directory.appending(path: "red.png")
        try pngData().write(to: file)
        let item = try await store.insert(filePayload(file), source: nil)
        try FileManager.default.removeItem(at: file)
        let payload = try await store.payload(item.id)
        #expect(await store.previewImage(for: item, payload: payload) != nil)
    }

    @Test func `backfills thumbnails for old file entries`() async throws {
        let (store, directory) = try makeStore()
        let file = directory.appending(path: "red.png")
        try pngData().write(to: file)
        let item = try await store.insert(filePayload(file), source: nil)
        // 模拟升级前保存的条目：缩略图为空
        let database = try SQLiteDatabase(path: directory.appending(path: "history.sqlite").path)
        try database.query("UPDATE clip SET thumbnail = NULL WHERE id = ?", [.int(item.id)])
        #expect(try await store.backfillFileThumbnails() == 1)
        #expect(try await store.thumbnail(item.id) != nil)
        #expect(try await store.items(matching: "", limit: 10).first?.hasThumbnail == true)
    }
}
