import AppKit
@testable import FeatureScreenshot
import Foundation
import MAIOKit
import Testing

struct HistoryRetentionTests {
    func record(_ id: String, daysAgo: Double, bytes: Int64, pinned: Bool = false) -> ScreenshotRecord {
        ScreenshotRecord(
            id: id, createdAt: Date(timeIntervalSince1970: 1_800_000_000 - daysAgo * 86400), pixelWidth: 1,
            pixelHeight: 1, sourceApp: nil, ocrText: nil, bytes: bytes, pinned: pinned,
        )
    }

    @Test func `over limit removes oldest unpinned first`() {
        let records = [
            record("new", daysAgo: 0, bytes: 100),
            record("old-pinned", daysAgo: 9, bytes: 100, pinned: true),
            record("old", daysAgo: 8, bytes: 100),
            record("mid", daysAgo: 4, bytes: 100),
        ]
        #expect(HistoryRetention.overLimit(records, limit: 250) == ["old", "mid"])
        #expect(HistoryRetention.overLimit(records, limit: nil).isEmpty)
        #expect(HistoryRetention.oldest(records, bytes: 150) == ["old", "mid"])
        #expect(HistoryRetention.before(records, date: Date(timeIntervalSince1970: 1_800_000_000 - 5 * 86400)) == ["old"])
    }

    @Test func `search and grouping`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        var first = record("a", daysAgo: 0, bytes: 1)
        first.ocrText = "Hello 世界"
        var second = record("b", daysAgo: 0.01, bytes: 1)
        second.sourceApp = "com.apple.Safari"
        let third = record("c", daysAgo: 3, bytes: 1)
        let records = [third, second, first]
        #expect(HistorySearch.filter(records, query: "世界", calendar: calendar).map(\.id) == ["a"])
        #expect(HistorySearch.filter(records, query: "safari", calendar: calendar).map(\.id) == ["b"])
        #expect(HistorySearch.filter(records, query: "2027-01-15", calendar: calendar).map(\.id) == ["b", "a"])
        let groups = HistorySearch.groupByDay(records, calendar: calendar)
        #expect(groups.map { $0.records.map(\.id) } == [["a", "b"], ["c"]])
    }
}

struct PinStateTests {
    @Test func `zoom keeps the anchor and clamps`() {
        var state = PinState(imageSize: CGSize(width: 200, height: 100))
        let origin = state.zoom(by: 2, anchor: CGPoint(x: 0.5, y: 0.5), contentOrigin: CGPoint(x: 100, y: 100))
        #expect(state.contentSize == CGSize(width: 400, height: 200))
        #expect(origin == CGPoint(x: 0, y: 50))
        _ = state.zoom(by: 100, anchor: .zero, contentOrigin: .zero)
        #expect(state.zoom == 5)
        _ = state.zoom(by: 0.0001, anchor: .zero, contentOrigin: .zero)
        #expect(state.zoom == 0.1)
    }

    @Test func `steps are five percent and snap to multiples`() {
        var state = PinState(imageSize: CGSize(width: 100, height: 100))
        _ = state.zoom(steps: 1, anchor: .zero, contentOrigin: .zero)
        #expect(abs(state.zoom - 1.05) < 0.0001)
        state.zoom = 0.873
        _ = state.zoom(steps: -1, anchor: .zero, contentOrigin: .zero)
        #expect(abs(state.zoom - 0.80) < 0.0001)
        state.stepOpacity(-1)
        #expect(abs(state.opacity - 0.95) < 0.0001)
        state.setOpacity(0.12)
        state.stepOpacity(-3)
        #expect(state.opacity == 0.1)
        #expect(PinControls() == PinControls(zoomModifier: .none, opacityModifier: .command))
    }

    @Test func `rotation swaps size and opacity keys`() {
        var state = PinState(imageSize: CGSize(width: 200, height: 100))
        state.rotate(clockwise: true)
        #expect(state.contentSize == CGSize(width: 100, height: 200))
        state.rotate(clockwise: false)
        state.rotate(clockwise: false)
        #expect(state.quarterTurns == 3)
        #expect(state.windowSize == CGSize(width: 100 + PinState.margin * 2, height: 200 + PinState.margin * 2))
        #expect(PinState.opacity(forDigit: 0) == 1)
        #expect(PinState.opacity(forDigit: 3) == 0.3)
        state.setOpacity(0)
        #expect(state.opacity == 0.1)
    }
}

struct PinInfrastructureTests {
    func image(width: Int, height: Int) throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // 左上角一个红色像素
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: height - 1, width: 1, height: 1))
        return try #require(context.makeImage())
    }

    @Test func `rotating clockwise moves top-left to top-right`() throws {
        let rotated = try #require(ImageRotation.rotated(image(width: 4, height: 2), quarterTurns: 1))
        #expect(rotated.width == 2)
        #expect(rotated.height == 4)
        #expect(PixelSampler.color(in: rotated, x: 1, y: 0)?.red == 255)
        #expect(PixelSampler.color(in: rotated, x: 1, y: 0)?.green == 0)
    }

    @Test @MainActor func `text renders to an image`() throws {
        let content = try #require(PasteboardImage.render(text: "贴图测试\nsecond line", scale: 2))
        #expect(content.isText)
        #expect(content.image.width > 100)
        #expect(content.image.height > content.image.width / 10)
    }

    @Test @MainActor func `edit context converts annotations and fits the display`() throws {
        let original = try image(width: 400, height: 200)
        let display = FrozenDisplay(
            display: DisplayInfo(id: 1, bounds: CGRect(x: 0, y: 0, width: 1000, height: 800)), image: original,
        )
        let counter = Annotation(shape: .counter(center: CGPoint(x: 10, y: 10), number: 1, radius: 10), color: .red, lineWidth: 0)
        let context = try #require(ScreenshotController.editContext(
            original: original, recordScale: 2, annotations: [counter], center: CGPoint(x: 500, y: 400), frozen: [display],
        ))
        // 这个"显示器"的缩放是 400 / 1000 = 0.4，原图 1:1 显示时 1000×500 pt，超过 90%，所以缩小
        #expect(context.rect.width <= 900)
        #expect(abs(context.rect.midX - 500) <= 1)
        let factor = 2 / context.source.scale
        #expect(context.annotations.first?.shape == .counter(
            center: CGPoint(x: context.rect.minX + 10 * factor, y: context.rect.minY + 10 * factor),
            number: 1, radius: 10 * factor,
        ))
    }

    @Test func `history store updates and deletes`() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "maio-shot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let png = try #require(ImageExporter.pngData(image(width: 20, height: 10)))
        let store = try ScreenshotHistoryStore(directory: directory)
        let first = try await store.add(
            .init(original: png, pixelWidth: 20, pixelHeight: 10, scale: 2),
            sourceApp: nil,
            date: Date(),
        )
        let second = try await store.add(
            .init(original: png, pixelWidth: 20, pixelHeight: 10, scale: 2),
            sourceApp: nil,
            date: Date(),
        )
        try await store.update(id: first.id, rendered: png, annotations: Data("[]".utf8))
        #expect(await store.record(id: first.id)?.hasAnnotations == true)
        let updated = try #require(await store.record(id: first.id))
        #expect(await store.finalImageURL(for: updated).lastPathComponent == "rendered.png")
        try await store.update(id: first.id, rendered: nil, annotations: nil)
        #expect(await store.record(id: first.id)?.hasAnnotations == false)
        try await store.setPinned(true, id: first.id)
        #expect(try await store.enforce(limit: 1) == 1)
        #expect(await store.records.map(\.id) == [first.id])
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: second.id).path))
        #expect(await store.stats.pinnedCount == 1)
    }
}

struct ScreenshotSettingsMigrationTests {
    @Test func `old control zoom modifier becomes none`() throws {
        var json = JSONValue.object(["pinZoomModifier": .string("control"), "pinOpacityModifier": .string("command")])
        try ScreenshotSettings.migrate(&json, from: 1)
        #expect(json.objectValue?["pinZoomModifier"] == .string("none"))
        #expect(json.objectValue?["pinOpacityModifier"] == .string("command"))
        var custom = JSONValue.object(["pinZoomModifier": .string("option")])
        try ScreenshotSettings.migrate(&custom, from: 1)
        #expect(custom.objectValue?["pinZoomModifier"] == .string("option"))
    }
}
