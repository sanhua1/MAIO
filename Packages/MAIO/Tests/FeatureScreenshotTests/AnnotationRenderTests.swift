import AppKit
@testable import FeatureScreenshot
import Foundation
import Testing

/// 渲染测试：输出和屏幕显示用同一套代码，这里检查方向、位置和像素换算。
/// 设置环境变量 MAIO_RENDER_SAMPLE=路径 时，会把包含全部工具的样图写到这个路径，方便人工查看。
@MainActor
struct AnnotationRenderTests {
    /// 400×300 pt、2 倍像素的"屏幕"：上半白、下半带文字
    func makeSource() throws -> EffectSource {
        let width = 800, height = 600
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // 左上角画一块灰色（CGContext 原点在左下，所以 y 要换算）
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: height - 40, width: 40, height: 40))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for row in 0 ..< 6 {
            NSAttributedString(string: "MAIO 截图标注测试 The quick brown fox \(row)", attributes: [
                .font: NSFont.systemFont(ofSize: 28), .foregroundColor: NSColor.black,
            ]).draw(at: CGPoint(x: 20, y: 40 + row * 44))
        }
        NSGraphicsContext.restoreGraphicsState()
        return try EffectSource(image: #require(context.makeImage()), origin: CGPoint(x: 1000, y: 0), scale: 2)
    }

    func color(of image: CGImage, x: Int, y: Int) -> SampledColor? {
        PixelSampler.color(in: image, x: x, y: y)
    }

    @Test func `output keeps orientation and pixel scale`() throws {
        let source = try makeSource()
        let selection = CGRect(x: 1000, y: 0, width: 100, height: 50)
        let filled = Annotation(
            shape: .rectangle(CGRect(x: 1050, y: 10, width: 20, height: 10), filled: true, rounded: false),
            color: .blue, lineWidth: 2,
        )
        let output = try #require(AnnotationRenderer.renderOutput([filled], selection: selection, source: source))
        #expect(output.width == 200)
        #expect(output.height == 100)
        // 左上角的灰块还在左上角
        let gray = try #require(color(of: output, x: 5, y: 5))
        #expect(gray.red < 200 && gray.red == gray.green)
        // 蓝色矩形：pt (50, 10)～(70, 20) → 像素 (100, 20)～(140, 40)
        #expect(color(of: output, x: 120, y: 30) == SampledColor(red: 0, green: 122, blue: 255))
        #expect(color(of: output, x: 120, y: 50) == SampledColor(red: 255, green: 255, blue: 255))
    }

    @Test func `mosaic hides original pixels`() throws {
        let source = try makeSource()
        let selection = CGRect(x: 1000, y: 0, width: 400, height: 300)
        let mosaic = Annotation(
            shape: .mosaic(CGRect(x: 1000, y: 0, width: 40, height: 40), blockSize: 20),
            color: .red,
            lineWidth: 0,
        )
        let output = try #require(AnnotationRenderer.renderOutput([mosaic], selection: selection, source: source))
        // 灰块（0～20 pt）和白底在同一个 20 pt 的块里被平均
        let corner = try #require(color(of: output, x: 2, y: 2))
        let inside = try #require(color(of: output, x: 38, y: 38))
        #expect(corner == inside)
    }

    @Test func `renders every tool`() throws {
        let source = try makeSource()
        let selection = CGRect(x: 1000, y: 0, width: 400, height: 300)
        let items = Self.sampleItems(offset: CGPoint(x: 1000, y: 0))
        let output = try #require(AnnotationRenderer.renderOutput(items, selection: selection, source: source))
        #expect(output.width == 800)
        if let path = ProcessInfo.processInfo.environment["MAIO_RENDER_SAMPLE"], let png = ImageExporter.pngData(output) {
            try png.write(to: URL(fileURLWithPath: path))
        }
    }

    static func sampleItems(offset: CGPoint) -> [Annotation] {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: offset.x + x, y: offset.y + y)
        }
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(origin: p(x, y), size: CGSize(width: w, height: h))
        }
        var text = TextBox(
            origin: p(220, 200), string: "文字 Text", fontSize: 18, bold: true, decoration: .background,
            backgroundColor: .yellow,
        )
        text.size = TextRendering.size(of: text)
        var outline = TextBox(
            origin: p(220, 240), string: "描边文字", fontSize: 20, bold: false, decoration: .outline,
            backgroundColor: .black,
        )
        outline.size = TextRendering.size(of: outline)
        return [
            Annotation(shape: .rectangle(r(10, 10, 80, 50), filled: false, rounded: true), color: .red, lineWidth: 4),
            Annotation(shape: .ellipse(r(100, 10, 80, 50), filled: false), color: .green, lineWidth: 4),
            Annotation(shape: .arrow(from: p(200, 60), to: p(280, 15)), color: .red, lineWidth: 4),
            Annotation(shape: .line(from: p(290, 15), to: p(390, 60), dashed: true), color: .blue, lineWidth: 3),
            Annotation(shape: .pen([p(10, 120), p(30, 100), p(50, 130), p(70, 95), p(90, 125)]), color: .purple, lineWidth: 4),
            Annotation(shape: .highlighter([p(10, 160), p(380, 160)]), color: .yellow, lineWidth: 16),
            Annotation(shape: .mosaic(r(10, 255, 150, 40), blockSize: 8), color: .red, lineWidth: 0),
            Annotation(shape: .blur(r(200, 160, 150, 40), radius: 6), color: .red, lineWidth: 0),
            Annotation(shape: .counter(center: p(40, 230), number: 1, radius: 13), color: .red, lineWidth: 0),
            Annotation(shape: .counter(center: p(90, 230), number: 12, radius: 13), color: .yellow, lineWidth: 0),
            Annotation(shape: .text(text), color: .blue, lineWidth: 0),
            Annotation(shape: .text(outline), color: .red, lineWidth: 0),
        ]
    }
}
