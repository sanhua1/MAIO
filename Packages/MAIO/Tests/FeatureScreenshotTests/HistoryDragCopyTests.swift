@testable import FeatureScreenshot
import Foundation
import Testing

struct HistoryDragCopyTests {
    @Test func `drag copy keeps the original and uses a readable name`() throws {
        let source = FileManager.default.temporaryDirectory.appending(path: "maio-drag-src-\(UUID().uuidString).png")
        try Data([1, 2, 3]).write(to: source)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let copy = try #require(HistoryDragCopy.make(from: source, date: date))
        #expect(copy.lastPathComponent == ScreenshotFileName.make(date: date) { _ in false })
        #expect(copy.path.hasPrefix(HistoryDragCopy.folder.path))
        #expect(try Data(contentsOf: copy) == Data([1, 2, 3]))
        #expect(FileManager.default.fileExists(atPath: source.path))
        // 同一张图拖两次不会撞名
        let again = try #require(HistoryDragCopy.make(from: source, date: date))
        #expect(again != copy)
    }
}
