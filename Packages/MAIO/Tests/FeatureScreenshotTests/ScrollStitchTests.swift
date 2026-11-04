import CoreGraphics
@testable import FeatureScreenshot
import Foundation
import Testing

/// 合成一份"长文档"，从不同位置截取窗口，模拟滚动
private struct Document {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    /// 有内容的行是随机灰度（真实截图每个格子有几十列、256 级灰度，区分度很高），段落之间有空白行
    init(width: Int, height: Int, seed: UInt64 = 7) {
        self.width = width
        self.height = height
        var state = seed
        func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state >> 33
        }
        pixels = []
        pixels.reserveCapacity(width * height)
        for y in 0 ..< height {
            let blank = (y / 12) % 5 == 4
            for _ in 0 ..< width {
                pixels.append(blank ? 255 : UInt8(next() % 220))
            }
        }
    }

    /// 窗口：显示文档第 offset 行开始的内容；顶部 header 行、底部 footer 行固定；左边 sidebar 列固定
    func view(offset: Int, height viewHeight: Int, header: Int = 0, footer: Int = 0, sidebar: Int = 0) -> GrayFrame {
        var result = [UInt8](repeating: 0, count: width * viewHeight)
        for y in 0 ..< viewHeight {
            for x in 0 ..< width {
                let value: UInt8 = if y < header {
                    UInt8(60 + (x * 7 + y * 3) % 120)
                } else if y >= viewHeight - footer {
                    UInt8(90 + (x * 5 + y) % 100)
                } else if x < sidebar {
                    UInt8((x * 11 + y * 13) % 200)
                } else {
                    pixels[(offset + y) * width + x]
                }
                result[y * width + x] = value
            }
        }
        return GrayFrame(width: width, height: viewHeight, pixels: result)
    }
}

/// 只比较不同像素的数量，失败时不会把关卡里的整张图打印出来
private func differences(_ first: [UInt8], _ second: [UInt8]) -> Int {
    guard first.count == second.count else { return max(first.count, second.count) }
    var count = 0
    for index in first.indices where first[index] != second[index] {
        count += 1
    }
    return count
}

struct ScrollMatcherTests {
    private let document = Document(width: 200, height: 1200)

    private func offset(_ previous: GrayFrame, _ current: GrayFrame) -> Int? {
        if case let .moved(match) = ScrollMatcher.match(previous: previous, current: current) {
            return match.offset
        }
        return nil
    }

    @Test func `finds the scroll offset`() {
        #expect(offset(document.view(offset: 0, height: 300), document.view(offset: 97, height: 300)) == 97)
        #expect(offset(document.view(offset: 0, height: 300), document.view(offset: 2, height: 300)) == 2)
    }

    @Test func `finds small and large offsets exactly`() {
        for shift in [1, 3, 17, 60, 140, 205] {
            #expect(offset(document.view(offset: 40, height: 300), document.view(offset: 40 + shift, height: 300)) == shift)
        }
    }

    @Test func `reports backward scrolling with a negative offset`() {
        #expect(offset(document.view(offset: 300, height: 300), document.view(offset: 240, height: 300)) == -60)
    }

    @Test func `tolerates small rendering noise`() {
        let previous = document.view(offset: 100, height: 300)
        let clean = document.view(offset: 175, height: 300)
        var pixels = clean.pixels
        for index in pixels.indices where index % 3 == 0 {
            pixels[index] = UInt8(min(255, Int(pixels[index]) + 6))
        }
        let noisy = GrayFrame(width: clean.width, height: clean.height, pixels: pixels)
        #expect(offset(previous, noisy) == 75)
    }

    @Test func `ignores sticky header, footer and sidebar`() {
        let first = document.view(offset: 50, height: 300, header: 30, footer: 20, sidebar: 40)
        let second = document.view(offset: 170, height: 300, header: 30, footer: 20, sidebar: 40)
        #expect(offset(first, second) == 120)
    }

    @Test func `identical frames are unchanged`() {
        let frame = document.view(offset: 10, height: 300)
        #expect(ScrollMatcher.match(previous: frame, current: frame) == .unchanged)
    }

    @Test func `no overlap is unknown instead of a wrong match`() {
        let other = Document(width: 200, height: 1200, seed: 99)
        let unrelated = ScrollMatcher.match(
            previous: document.view(offset: 0, height: 300),
            current: other.view(offset: 0, height: 300),
        )
        #expect(unrelated == .unknown)
        // 滚动超过画面的 70%：重叠太少，不冒险
        #expect(offset(document.view(offset: 0, height: 300), document.view(offset: 250, height: 300)) == nil)
    }

    @Test func `repeated rules do not decide the result`() {
        // 每一行都一样的竖线、每 20 行一条的分隔线：很多位移都"对得上"，不能随便选一个
        var pixels = [UInt8](repeating: 255, count: 200 * 1200)
        for y in 0 ..< 1200 {
            pixels[y * 200 + 60] = 0
            pixels[y * 200 + 140] = 0
            if y % 20 == 0 {
                for x in 30 ..< 170 {
                    pixels[y * 200 + x] = 0
                }
            }
        }
        let page = GrayFrame(width: 200, height: 1200, pixels: pixels)
        func view(_ top: Int) -> GrayFrame {
            GrayFrame(width: 200, height: 300, pixels: Array(page.pixels[(top * 200) ..< ((top + 300) * 200)]))
        }
        // 分不清就宁可不要：不能给出一个"看起来对"的错误位移
        if case let .moved(match) = ScrollMatcher.match(previous: view(0), current: view(37)) {
            Issue.record("重复内容不应给出位移：\(match)")
        }
    }
}

struct StitchPlanTests {
    @Test func `writes the bottom band when scrolling down`() {
        var plan = StitchPlan(frameHeight: 300)
        plan.begin()
        // shift 100：band = max(150, 75+100) = 175，写帧内 125..<300
        #expect(plan.append(frame: 1, offset: 100) == .written(125 ..< 300))
        #expect(plan.strips == [
            .init(frame: 0, start: 0, end: 225, top: 0),
            .init(frame: 1, start: 125, end: 300, top: 225),
        ])
        #expect(plan.canvasHeight == 400)
        #expect(plan.position == 100)
        // shift 20：band = 150，写帧内 150..<300
        #expect(plan.append(frame: 2, offset: 20) == .written(150 ..< 300))
        #expect(plan.canvasHeight == 420)
        #expect(plan.position == 120)
    }

    @Test func `scrolling back inside the canvas only moves the position`() {
        var plan = StitchPlan(frameHeight: 300)
        plan.begin()
        plan.append(frame: 1, offset: 100)
        #expect(plan.append(frame: 2, offset: -80) == .inside)
        #expect(plan.position == 20)
        #expect(plan.canvasHeight == 400)
        #expect(plan.strips.count == 2)
    }

    @Test func `scrolling back past the start extends the canvas upward`() {
        var plan = StitchPlan(frameHeight: 300)
        plan.begin()
        plan.append(frame: 1, offset: 100)
        #expect(plan.append(frame: 2, offset: -130) == .written(0 ..< 150))
        #expect(plan.position == 0)
        #expect(plan.canvasHeight == 430)
        #expect(plan.strips.first == .init(frame: 2, start: 0, end: 150, top: 0))
        // 画布没有空洞
        var covered = 0
        for strip in plan.strips {
            #expect(strip.top == covered)
            covered += strip.height
        }
        #expect(covered == plan.canvasHeight)
    }

    @Test func `matcher and plan rebuild the document with sticky header and footer`() {
        let document = Document(width: 160, height: 1500)
        let offsets = [0, 110, 230, 300, 420, 560, 600, 603, 700]
        let frames = offsets.map { document.view(offset: $0, height: 320, header: 24, footer: 16) }
        var plan = StitchPlan(frameHeight: 320)
        plan.begin()
        var position = 0
        for index in 1 ..< frames.count {
            guard case let .moved(match) = ScrollMatcher.match(previous: frames[index - 1], current: frames[index]) else {
                Issue.record("第 \(index) 帧没对上：\(ScrollMatcher.match(previous: frames[index - 1], current: frames[index]))")
                return
            }
            #expect(match.offset == offsets[index] - offsets[index - 1])
            plan.append(frame: index, offset: match.offset)
            position += match.offset
            #expect(plan.position == position)
        }
        var rows: [[UInt8]] = []
        for strip in plan.strips {
            for y in strip.start ..< strip.end {
                rows.append(Array(frames[strip.frame].pixels[(y * 160) ..< ((y + 1) * 160)]))
            }
        }
        // 头部只出现一次，正文是文档的连续内容，页脚只在最后
        let last = 700
        let content = (24 ..< (last + 320 - 16)).map { Array(document.pixels[($0 * 160) ..< (($0 + 1) * 160)]) }
        let flat = rows.flatMap { $0 }
        #expect(rows.count == 24 + content.count + 16)
        #expect(differences(Array(flat[(24 * 160) ..< ((24 + content.count) * 160)]), content.flatMap { $0 }) == 0)
    }

    @Test func `scrolling back then down again keeps the document continuous`() {
        let document = Document(width: 160, height: 1500)
        let frames = [0, 120, 240, 180, 300, 420].map { document.view(offset: $0, height: 300) }
        var plan = StitchPlan(frameHeight: 300)
        plan.begin()
        for index in 1 ..< frames.count {
            guard case let .moved(match) = ScrollMatcher.match(previous: frames[index - 1], current: frames[index]) else {
                Issue.record("第 \(index) 帧没对上")
                return
            }
            plan.append(frame: index, offset: match.offset)
        }
        #expect(plan.position == 420)
        #expect(plan.canvasHeight == 720)
        var rows: [[UInt8]] = []
        for strip in plan.strips {
            for y in strip.start ..< strip.end {
                rows.append(Array(frames[strip.frame].pixels[(y * 160) ..< ((y + 1) * 160)]))
            }
        }
        let content = (0 ..< 720).map { Array(document.pixels[($0 * 160) ..< (($0 + 1) * 160)]) }
        #expect(differences(rows.flatMap { $0 }, content.flatMap { $0 }) == 0)
    }
}

struct LongImageBuilderTests {
    private func image(_ frame: GrayFrame) -> CGImage? {
        let data = frame.pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: frame.width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent,
        )
    }

    @Test func `composes strips in order`() throws {
        let document = Document(width: 120, height: 900)
        let offsets = [0, 90, 200, 260, 262]
        let frames = offsets.map { document.view(offset: $0, height: 240, header: 20, footer: 12) }
        var builder = try LongImageBuilder(first: #require(image(frames[0])))
        for index in 1 ..< frames.count {
            try builder.append(#require(image(frames[index])), offset: offsets[index] - offsets[index - 1])
        }
        let gray = try #require(builder.compose().flatMap(GrayFrame.init))
        let last = 262
        #expect(gray.height == 20 + (last + 240 - 12 - 20) + 12)
        #expect(differences(Array(gray.pixels[0 ..< 120 * 20]), Array(frames[0].pixels[0 ..< 120 * 20])) == 0)
        let content = Array(document.pixels[(20 * 120) ..< ((last + 240 - 12) * 120)])
        #expect(differences(Array(gray.pixels[(20 * 120) ..< ((gray.height - 12) * 120)]), content) == 0)
        #expect(differences(
            Array(gray.pixels[((gray.height - 12) * 120)...]),
            Array(frames[frames.count - 1].pixels[((240 - 12) * 120)...]),
        ) == 0)
    }

    @Test func `preview keeps the aspect ratio of the stitched image`() throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue,
        ))
        let frame = try #require(context.makeImage())
        var builder = LongImageBuilder(first: frame, previewWidth: 100)
        builder.append(frame, offset: 150)
        let preview = try #require(builder.preview())
        #expect(builder.height == 450)
        #expect(preview.width == 100)
        #expect(preview.height == 113) // 450 × 0.25 四舍五入
    }
}
