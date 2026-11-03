import Dispatch
import MAIOKit
import Synchronization

/// 平滑滚动动画：在独立的高优先级队列上按屏幕刷新率逐帧发出像素滚动事件。
/// 不使用 CVDisplayLink（macOS 15 起已弃用），也不依赖主线程，主线程卡顿时滚动依然流畅。
final class SmoothScrollAnimator: Sendable {
    private struct State {
        var scroller: SmoothScroller
        var quantizer = PixelQuantizer()
        var timer: (any DispatchSourceTimer)?
    }

    private let state: Mutex<State>
    private let poster: any SyntheticEventPoster
    private let queue = DispatchQueue(label: "app.maio.scroll.animator", qos: .userInteractive)

    init(poster: any SyntheticEventPoster, parameters: SmoothScroller.Parameters) {
        self.poster = poster
        state = Mutex(State(scroller: SmoothScroller(parameters: parameters)))
    }

    /// 新的滚动输入（在 tap 线程上调用）。
    func add(y: Double, x: Double, parameters: SmoothScroller.Parameters) {
        state.withLock { state in
            state.scroller.parameters = parameters
            state.scroller.add(y: y, x: x)
            guard state.timer == nil else { return }
            state.timer = makeTimer(framesPerSecond: parameters.framesPerSecond)
        }
    }

    /// 立即停止（功能停用时）。
    func stop() {
        state.withLock { state in
            state.timer?.cancel()
            state.timer = nil
            state.scroller.reset()
            state.quantizer.reset()
        }
    }

    private func makeTimer(framesPerSecond: Double) -> any DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        let interval = DispatchTimeInterval.nanoseconds(Int(1_000_000_000 / framesPerSecond))
        timer.schedule(deadline: .now(), repeating: interval, leeway: .nanoseconds(0))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        return timer
    }

    private func tick() {
        let frame: (y: Double, x: Double)? = state.withLock { state in
            if let frame = state.scroller.nextFrame() {
                return state.quantizer.quantize(frame)
            }
            state.timer?.cancel()
            state.timer = nil
            state.quantizer.reset()
            return nil
        }
        // 不足 1 像素的帧不发送，余数累积到后面的帧（系统会把小数像素截断，见 PixelQuantizer）
        guard let frame, frame.y != 0 || frame.x != 0 else { return }
        poster.post(.scroll(deltaY: frame.y, deltaX: frame.x, phase: .none, momentumPhase: .none))
    }
}
