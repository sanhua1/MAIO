@testable import FeatureScroll
import MAIOKit
import Testing

struct ScrollPlannerTests {
    private func config(_ edit: (inout ScrollSettings) -> Void = { _ in }) -> ScrollConfig {
        var settings = ScrollSettings.defaultValue
        edit(&settings)
        return ScrollConfig(settings: settings, framesPerSecond: 120)
    }

    private func wheel(_ y: Double, _ x: Double = 0, continuous: Bool = false) -> PointerEvent {
        PointerEvent(scrollY: y, scrollX: x, device: .wheel, isContinuous: continuous)
    }

    private let env = RealtimeEnvironment(frontmostBundleID: nil, modifiers: [])

    @Test func `trackpad and synthetic events are untouched`() {
        let trackpad = PointerEvent(scrollY: 3, scrollX: 0, device: .trackpad, phase: .changed)
        #expect(ScrollPlanner.plan(trackpad, env, config()) == .untouched(trackpad))
        let synthetic = PointerEvent(scrollY: 3, scrollX: 0, device: .wheel, isSynthetic: true)
        #expect(ScrollPlanner.plan(synthetic, env, config()) == .untouched(synthetic))
    }

    @Test func `reverse only when smoothing is off`() {
        let plan = ScrollPlanner.plan(wheel(1, -2), env, config { $0.smoothEnabled = false })
        #expect(plan == ScrollPlan(passY: -1, passX: 2))
    }

    @Test func `smoothing consumes and applies step, speed and reverse`() {
        // 1 行 = 10 像素，小于步长 33.6 → 补到 33.6，再乘 2.7，反转后为负
        let plan = ScrollPlanner.plan(wheel(1), env, config())
        #expect(plan.consume)
        #expect(abs(plan.smoothY - -33.6 * 2.7) < 0.0001)
        #expect(plan.smoothX == 0)
    }

    @Test func `large deltas keep their size`() {
        let event = PointerEvent(scrollY: 8, scrollX: 0, pixelY: 80, device: .wheel)
        let plan = ScrollPlanner.plan(event, env, config { $0.reverseVertical = false })
        #expect(abs(plan.smoothY - 80 * 2.7) < 0.0001)
    }

    @Test func `continuous wheel is reversed but not smoothed`() {
        let plan = ScrollPlanner.plan(wheel(0.4, continuous: true), env, config())
        #expect(plan == ScrollPlan(passY: -0.4, passX: 0))
    }

    @Test func `command key disables smoothing to keep zoom working`() {
        let commandEnv = RealtimeEnvironment(frontmostBundleID: nil, modifiers: .command)
        let plan = ScrollPlanner.plan(wheel(1), commandEnv, config())
        #expect(!plan.hasSmoothing)
        #expect(plan.passY == -1)
    }

    @Test func `shift turns vertical into horizontal with horizontal preferences`() {
        let shiftEnv = RealtimeEnvironment(frontmostBundleID: nil, modifiers: .shift)
        let plan = ScrollPlanner.plan(wheel(1), shiftEnv, config { $0.reverseHorizontal = false })
        #expect(plan.consume)
        #expect(plan.smoothY == 0)
        #expect(plan.smoothX > 0)
    }

    @Test func `app exception uses target app before frontmost app`() {
        let cfg = config { $0.exceptions = [AppException(
            bundleID: "com.game",
            name: "Game",
            disableSmooth: true,
            disableReverse: true,
        )] }
        let pointingAtGame = RealtimeEnvironment(frontmostBundleID: "com.other", targetBundleID: "com.game", modifiers: [])
        #expect(ScrollPlanner.plan(wheel(1), pointingAtGame, cfg) == ScrollPlan(passY: 1, passX: 0))
        let gameFrontmostButPointingElsewhere = RealtimeEnvironment(
            frontmostBundleID: "com.game", targetBundleID: "com.other", modifiers: [],
        )
        #expect(ScrollPlanner.plan(wheel(1), gameFrontmostButPointingElsewhere, cfg).consume)
    }

    @Test func `only one axis smoothed passes the other through`() {
        let plan = ScrollPlanner.plan(wheel(1, 1), env, config { $0.smoothHorizontal = false })
        #expect(!plan.consume)
        #expect(plan.passY == 0)
        #expect(plan.passX == -1)
        #expect(plan.smoothY != 0)
    }
}
