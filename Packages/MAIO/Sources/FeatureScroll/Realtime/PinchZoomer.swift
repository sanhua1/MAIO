import CoreGraphics
import Dispatch
import MAIOKit
import Synchronization

/// 发出触控板捏合手势：第一格滚轮时 began，之后逐帧 changed，松开修饰键（或停下一会儿）时 ended。
/// App 看到的就是一次完整的双指捏合，预览、浏览器、地图等都按自己的方式平滑缩放。
final class PinchZoomer: Sendable {
    private struct State {
        var easer = ZoomEaser()
        var isActive = false
        var idleFrames = 0
        var modifier: KeyModifiers = .command
        var timer: (any DispatchSourceTimer)?
    }

    static let framesPerSecond = 120.0
    /// 停下这么多帧（0.5 秒）还没有新的滚动，就结束这次捏合
    static let maximumIdleFrames = 60

    private let state = Mutex(State())
    private let poster: any SyntheticEventPoster
    private let queue = DispatchQueue(label: "app.maio.scroll.zoom", qos: .userInteractive)

    init(poster: any SyntheticEventPoster) {
        self.poster = poster
    }

    /// 新的缩放输入（tap 线程）
    func add(_ magnification: Double, modifier: KeyModifiers) {
        state.withLock { state in
            state.easer.add(magnification)
            state.modifier = modifier
            state.idleFrames = 0
            if !state.isActive {
                state.isActive = true
                poster.post(.magnify(phase: .began, magnification: 0))
            }
            if state.timer == nil {
                state.timer = makeTimer()
            }
        }
    }

    /// 立即结束（功能停用时）
    func stop() {
        state.withLock { state in
            finish(&state)
        }
    }

    private func makeTimer() -> any DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        let interval = DispatchTimeInterval.nanoseconds(Int(1_000_000_000 / Self.framesPerSecond))
        timer.schedule(deadline: .now(), repeating: interval, leeway: .nanoseconds(0))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        return timer
    }

    private func tick() {
        state.withLock { state in
            if let step = state.easer.next() {
                poster.post(.magnify(phase: .changed, magnification: step))
                return
            }
            state.idleFrames += 1
            if !Self.isHeld(state.modifier) || state.idleFrames >= Self.maximumIdleFrames {
                finish(&state)
            }
        }
    }

    private func finish(_ state: inout State) {
        state.timer?.cancel()
        state.timer = nil
        state.easer.reset()
        state.idleFrames = 0
        if state.isActive {
            state.isActive = false
            poster.post(.magnify(phase: .ended, magnification: 0))
        }
    }

    /// 修饰键现在还按着吗（直接查系统的键盘状态）
    private static func isHeld(_ modifier: KeyModifiers) -> Bool {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        var held: KeyModifiers = []
        if flags.contains(.maskCommand) {
            held.insert(.command)
        }
        if flags.contains(.maskAlternate) {
            held.insert(.option)
        }
        if flags.contains(.maskControl) {
            held.insert(.control)
        }
        return held.contains(modifier)
    }
}
