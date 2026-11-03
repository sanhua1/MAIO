@testable import FeatureScreenshot
import Testing

struct WheelStepperTests {
    @Test func `one smoothed wheel notch is one step`() {
        var stepper = WheelStepper()
        // 平滑滚动把一格滚轮拆成 0.3 秒内的十几个像素事件
        let steps = (0 ..< 15).map { index in
            stepper.feed(delta: 6, precise: true, time: 10 + Double(index) * 0.02)
        }
        #expect(steps.reduce(0, +) == 1)
    }

    @Test func `pauses start a new step and direction changes count`() {
        var stepper = WheelStepper()
        #expect(stepper.feed(delta: 1, precise: false, time: 0) == 1)
        #expect(stepper.feed(delta: 1, precise: false, time: 0.5) == 1)
        #expect(stepper.feed(delta: -1, precise: false, time: 0.55) == -1)
        #expect(stepper.feed(delta: 0, precise: false, time: 0.6) == 0)
    }

    @Test func `continuous scrolling keeps stepping`() {
        var stepper = WheelStepper()
        let steps = (0 ..< 30).map { index in
            stepper.feed(delta: 20, precise: true, time: Double(index) * 0.016)
        }
        // 第一步立即，之后每累积 120 pt 一步：(29 × 20) / 120 = 4
        #expect(steps.reduce(0, +) == 5)
    }
}
