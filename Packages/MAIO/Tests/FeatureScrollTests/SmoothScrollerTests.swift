@testable import FeatureScroll
import MAIOTesting
import Testing

struct SmoothScrollerTests {
    private func run(_ scroller: inout SmoothScroller, maxFrames: Int = 2000) -> [(y: Double, x: Double)] {
        var frames: [(y: Double, x: Double)] = []
        while let frame = scroller.nextFrame(), frames.count < maxFrames {
            frames.append(frame)
        }
        return frames
    }

    @Test func `delivers almost the whole distance and then stops`() {
        var scroller = SmoothScroller(parameters: .init(duration: 4.35, framesPerSecond: 120))
        scroller.add(y: 300, x: 0)
        let frames = run(&scroller)
        let total = frames.map(\.y).reduce(0, +)
        #expect(abs(total - 300) < 5, "实际 \(total)")
        #expect(frames.count < 600, "动画应在 5 秒内结束，实际 \(frames.count) 帧")
        #expect(scroller.isIdle)
    }

    @Test func `output is smooth and never overshoots direction`() {
        var scroller = SmoothScroller(parameters: .init(duration: 4.35, framesPerSecond: 60))
        scroller.add(y: -200, x: 0)
        let frames = run(&scroller)
        #expect(frames.allSatisfy { $0.y <= 0 })
    }

    @Test func `same frame rate independent duration`() {
        func seconds(_ fps: Double) -> Double {
            var scroller = SmoothScroller(parameters: .init(duration: 4.35, framesPerSecond: fps))
            scroller.add(y: 300, x: 0)
            return Double(run(&scroller).count) / fps
        }
        #expect(abs(seconds(60) - seconds(120)) < 0.1, "60Hz 与 120Hz 的动画时长应接近")
    }

    @Test func `reversing direction stops immediately`() {
        var scroller = SmoothScroller(parameters: .init(duration: 4.35, framesPerSecond: 120))
        scroller.add(y: 300, x: 0)
        for _ in 0 ..< 5 {
            _ = scroller.nextFrame()
        }
        scroller.add(y: -100, x: 0)
        let frames = run(&scroller)
        let total = frames.map(\.y).reduce(0, +)
        #expect(total < 0)
        #expect(abs(total - -100) < 5, "反向后应只走新的 100 像素，实际 \(total)")
    }

    @Test func `same direction accumulates`() {
        var scroller = SmoothScroller(parameters: .init(duration: 4.35, framesPerSecond: 120))
        scroller.add(y: 100, x: 0)
        _ = scroller.nextFrame()
        scroller.add(y: 100, x: 0)
        let total = run(&scroller).map(\.y).reduce(0, +)
        #expect(total > 150)
    }

    @Test func `longer duration lasts longer`() {
        func frames(_ duration: Double) -> Int {
            var scroller = SmoothScroller(parameters: .init(duration: duration, framesPerSecond: 120))
            scroller.add(y: 300, x: 0)
            return run(&scroller).count
        }
        #expect(frames(1) < frames(4.35))
    }
}

struct ScrollFeatureTests {
    @Test @MainActor func `registers filter and commands, cleans up on deactivate`() async throws {
        let context = FakeFeatureContext(featureID: "scroll")
        let feature = ScrollFeature(context: context)
        try await feature.activate()
        #expect(context.fakeInput.filters.count == 1)
        #expect(Set(context.fakeCommands.descriptors.keys) == Set(ScrollFeature.manifest.commands.map(\.id)))
        try await context.commands.perform("scroll.toggleSmooth")
        #expect(context.fakeSettings.load(ScrollSettings.self).smoothEnabled == false)
        await feature.deactivate()
        #expect(context.fakeInput.filters.isEmpty)
    }
}

struct PixelQuantizerTests {
    @Test func `carries fractions so the total is preserved`() {
        var quantizer = PixelQuantizer()
        var total = 0.0
        for _ in 0 ..< 10 {
            let out = quantizer.quantize((y: -0.35, x: 0.25))
            #expect(out.y == out.y.rounded())
            total += out.y
        }
        #expect(total == -3)
    }
}
