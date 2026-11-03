@testable import FeatureClipboard
import Foundation
import Testing

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
}
