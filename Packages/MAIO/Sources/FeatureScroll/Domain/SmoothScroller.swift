import Foundation

/// 平滑滚动动画的状态机（纯逻辑，可单测）。
///
/// 思路参考 Mos（references/Mos/Mos/ScrollCore/ScrollPoster.swift、ScrollFilter.swift）：
/// 输入累加到"目标位移"；每帧把当前位移向目标推进一个比例；输出再经过一阶低通滤波，
/// 剩余位移和输出都小于死区时结束。这里是独立实现，并按帧率换算，使 60Hz 与 120Hz 屏幕手感一致。
struct SmoothScroller {
    struct Parameters: Sendable, Equatable {
        /// 每帧推进剩余位移的比例（已按帧率换算）
        var transition: Double
        var framesPerSecond: Double
        /// 输出滤波系数（每帧）
        var smoothing: Double
        /// 小于这个像素数视为结束
        var deadZone = 1.0

        /// duration：1–5，越大动画越长。60Hz 下的比例与 Mos 相同：1 - √(duration / 5.2)。
        init(duration: Double, framesPerSecond: Double) {
            let fps = max(30, framesPerSecond)
            let perFrameAt60 = max(0.01, 1 - (min(max(duration, 0), 5) / 5.2).squareRoot())
            transition = Self.rescale(perFrameAt60, fps: fps)
            smoothing = Self.rescale(0.23, fps: fps)
            self.framesPerSecond = fps
        }

        /// 把 60Hz 下"每帧比例"换算到其他帧率，使单位时间内的衰减相同。
        static func rescale(_ perFrameAt60: Double, fps: Double) -> Double {
            1 - pow(1 - perFrameAt60, 60 / fps)
        }
    }

    var parameters: Parameters
    private var target = (y: 0.0, x: 0.0)
    private var current = (y: 0.0, x: 0.0)
    private var output = (y: 0.0, x: 0.0)

    init(parameters: Parameters) {
        self.parameters = parameters
    }

    var isIdle: Bool {
        target == (0, 0) && current == (0, 0) && output == (0, 0)
    }

    /// 新的滚动输入（像素）。同方向累加；反方向时清空，立即转向。
    mutating func add(y: Double, x: Double) {
        Self.accumulate(&target.y, &current.y, &output.y, y)
        Self.accumulate(&target.x, &current.x, &output.x, x)
    }

    /// 计算下一帧要发出的位移；动画结束时返回 nil 并复位。
    mutating func nextFrame() -> (y: Double, x: Double)? {
        let step = (y: (target.y - current.y) * parameters.transition, x: (target.x - current.x) * parameters.transition)
        current.y += step.y
        current.x += step.x
        output.y += (step.y - output.y) * parameters.smoothing
        output.x += (step.x - output.x) * parameters.smoothing
        let remaining = max(abs(target.y - current.y), abs(target.x - current.x))
        let emitted = max(abs(output.y), abs(output.x))
        if remaining <= parameters.deadZone, emitted <= parameters.deadZone {
            reset()
            return nil
        }
        return output
    }

    mutating func reset() {
        target = (0, 0)
        current = (0, 0)
        output = (0, 0)
    }

    private static func accumulate(_ target: inout Double, _ current: inout Double, _ output: inout Double, _ value: Double) {
        guard value != 0 else { return }
        let remaining = target - current
        if remaining == 0 || (remaining > 0) == (value > 0) {
            target += value
        } else {
            target = current + value
            output = 0
        }
    }
}
