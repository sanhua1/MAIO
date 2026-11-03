import CoreGraphics
@testable import FeatureScreenshot
import Foundation
import Testing

struct WindowPickerTests {
    func window(
        _ id: UInt32,
        _ frame: CGRect,
        pid: Int32 = 10,
        layer: Int = 0,
        alpha: Double = 1,
        owner: String = "App",
        bundle: String? = "com.example",
    ) -> WindowInfo {
        WindowInfo(id: id, pid: pid, frame: frame, layer: layer, alpha: alpha, ownerName: owner, bundleID: bundle)
    }

    @Test func `filters system and own windows`() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let windows = [
            window(
                1,
                CGRect(x: 0, y: 1234, width: 28, height: 40),
                pid: 419,
                layer: 2_147_483_630,
                owner: "Window Server",
                bundle: nil,
            ),
            window(2, screen, pid: 1064, layer: 20, owner: "程序坞", bundle: WindowPicker.dockBundleID),
            window(3, CGRect(x: 0, y: 0, width: 300, height: 300), pid: 99),
            window(4, CGRect(x: 0, y: 0, width: 4, height: 4)),
            window(5, CGRect(x: 0, y: 0, width: 300, height: 300), alpha: 0),
            window(6, CGRect(x: 0, y: 30, width: 2560, height: 1358)),
        ]
        let candidates = WindowPicker.candidates(windows, excludingPID: 99, displays: [screen])
        #expect(candidates.map(\.id) == [6])
        #expect(WindowPicker.window(at: CGPoint(x: 10, y: 10), in: candidates) == nil)
        #expect(WindowPicker.window(at: CGPoint(x: 10, y: 100), in: candidates)?.id == 6)
    }

    @Test func `topmost window wins`() {
        let candidates = [
            window(1, CGRect(x: 100, y: 100, width: 100, height: 100)),
            window(2, CGRect(x: 0, y: 0, width: 500, height: 500)),
        ]
        #expect(WindowPicker.window(at: CGPoint(x: 150, y: 150), in: candidates)?.id == 1)
        #expect(WindowPicker.window(at: CGPoint(x: 50, y: 50), in: candidates)?.id == 2)
    }
}

struct ScreenshotFormattingTests {
    @Test func `formats colors`() {
        let color = SampledColor(red: 26, green: 43, blue: 5)
        #expect(ColorFormat.hex.string(color) == "#1A2B05")
        #expect(ColorFormat.rgb.string(color) == "rgb(26, 43, 5)")
        #expect(ColorFormat.hex.next == .rgb)
    }

    @Test func `file name uses time and avoids collisions`() throws {
        let zone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let date = Date(timeIntervalSince1970: 1_793_685_933) // 2026-11-03 14:05:33 +08:00
        let first = ScreenshotFileName.make(date: date, timeZone: zone) { _ in false }
        #expect(first == "MAIO 2026-11-03 14.05.33.png")
        let second = ScreenshotFileName.make(date: date, timeZone: zone) { $0 == first }
        #expect(second == "MAIO 2026-11-03 14.05.33 2.png")
    }

    @Test func `toolbar goes below, then above, then inside`() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = CGSize(width: 120, height: 34)
        let below = OverlayLayout.toolbarFrame(
            size: size,
            selection: CGRect(x: 100, y: 100, width: 300, height: 200),
            bounds: bounds,
        )
        #expect(below.origin == CGPoint(x: 280, y: 308))
        let above = OverlayLayout.toolbarFrame(
            size: size,
            selection: CGRect(x: 100, y: 500, width: 300, height: 290),
            bounds: bounds,
        )
        #expect(above.minY == 458)
        let inside = OverlayLayout.toolbarFrame(size: size, selection: bounds, bounds: bounds)
        #expect(inside.maxY == 792)
        #expect(inside.maxX == 992)
    }

    @Test func `magnifier flips near edges`() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = CGSize(width: 120, height: 174)
        #expect(OverlayLayout.magnifierFrame(size: size, cursor: CGPoint(x: 10, y: 10), bounds: bounds).origin == CGPoint(
            x: 30,
            y: 30,
        ))
        let flipped = OverlayLayout.magnifierFrame(size: size, cursor: CGPoint(x: 990, y: 790), bounds: bounds)
        #expect(flipped.origin == CGPoint(x: 990 - 20 - 120, y: 790 - 20 - 174))
    }
}

struct ScreenshotInfrastructureTests {
    func solidImage(width: Int, height: Int, rgb: (UInt8, UInt8, UInt8)) throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        context.setFillColor(CGColor(
            srgbRed: CGFloat(rgb.0) / 255, green: CGFloat(rgb.1) / 255, blue: CGFloat(rgb.2) / 255, alpha: 1,
        ))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // 左上角一个像素涂成白色（CGContext 原点在左下，所以是 y = height - 1）
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: height - 1, width: 1, height: 1))
        return try #require(context.makeImage())
    }

    @Test func `samples pixel colors with top-left origin`() throws {
        let image = try solidImage(width: 4, height: 4, rgb: (26, 43, 60))
        #expect(PixelSampler.color(in: image, x: 0, y: 0) == SampledColor(red: 255, green: 255, blue: 255))
        #expect(PixelSampler.color(in: image, x: 2, y: 3) == SampledColor(red: 26, green: 43, blue: 60))
        #expect(PixelSampler.color(in: image, x: 4, y: 0) == nil)
    }

    @Test func `history store writes files and index`() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "maio-shot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try solidImage(width: 40, height: 20, rgb: (1, 2, 3))
        let png = try #require(ImageExporter.pngData(image))
        let store = try ScreenshotHistoryStore(directory: directory)
        let entry = ScreenshotHistoryStore.Entry(
            original: png, rendered: png, annotations: Data("[]".utf8), pixelWidth: 40, pixelHeight: 20, scale: 2,
        )
        let record = try await store.add(entry, sourceApp: "com.example", date: Date())
        let folder = directory.appending(path: record.id)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "original.png").path))
        for name in ["thumb.png", "rendered.png", "annotations.json"] {
            #expect(FileManager.default.fileExists(atPath: folder.appending(path: name).path))
        }
        let reopened = try ScreenshotHistoryStore(directory: directory)
        #expect(await reopened.records.map(\.id) == [record.id])
        #expect(await reopened.records.first?.sourceApp == "com.example")
        #expect(await reopened.records.first?.hasAnnotations == true)
        #expect(await reopened.records.first?.scale == 2)
    }

    @Test func `corrupt index is rebuilt from folders`() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "maio-shot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try solidImage(width: 8, height: 8, rgb: (1, 2, 3))
        let png = try #require(ImageExporter.pngData(image))
        let record = try await ScreenshotHistoryStore(directory: directory)
            .add(.init(original: png, pixelWidth: 8, pixelHeight: 8, scale: 1), sourceApp: nil, date: Date())
        try Data("garbage".utf8).write(to: directory.appending(path: "index.json"))
        let reopened = try ScreenshotHistoryStore(directory: directory)
        #expect(await reopened.records.map(\.id) == [record.id])
    }

    @Test func `saves with generated name`() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "maio-save-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try ImageExporter.save(png: Data([1, 2, 3]), toDirectory: directory, date: Date())
        #expect(url.lastPathComponent.hasPrefix("MAIO "))
        #expect(try Data(contentsOf: url) == Data([1, 2, 3]))
    }
}

struct CaptureTimeoutTests {
    @Test func `returns result before timeout`() async throws {
        let value = try await withTimeout(.seconds(1)) { 42 }
        #expect(value == 42)
    }

    @Test func `throws when the operation never returns`() async {
        let started = ContinuousClock.now
        await #expect(throws: CaptureError.self) {
            try await withTimeout(.milliseconds(50)) {
                try await Task.sleep(for: .seconds(5))
                return 1
            }
        }
        #expect(ContinuousClock.now - started < .seconds(1))
    }
}
