import CoreGraphics

/// 把滚轮事件换算成"加一 / 减一"（调整序号、大小档位）。
///
/// 滚一格滚轮不一定只来一个事件：开了平滑滚动（MAIO 自己的滚动功能、Mos 等）时会变成一串连续的小事件，
/// 触控板更是一次手势几十个事件。规则：
/// - 停顿超过 `burstGap` 后的第一个事件立即走一步（滚一格 = 一步）；
/// - 同一串事件里继续累积，超过阈值才再走一步（一直滚动时仍然可以连续调整）；
/// - 换方向视为新的一串。
struct WheelStepper {
    static let burstGap = 0.25

    /// 同一串事件里再走一步需要的累积量：像素滚动按 pt，按行滚动按行
    let preciseThreshold: CGFloat
    let lineThreshold: CGFloat

    private var lastTime: Double?
    private var accumulated: CGFloat = 0
    private var direction: CGFloat = 0

    /// 默认值适合调整序号（一格一步）；调整大小时用更小的阈值，滚得越多变化越大
    init(preciseThreshold: CGFloat = 120, lineThreshold: CGFloat = 4) {
        self.preciseThreshold = preciseThreshold
        self.lineThreshold = lineThreshold
    }

    /// 返回 +1、-1 或 0。delta 为正表示向上滚（增大）。
    mutating func feed(delta: CGFloat, precise: Bool, time: Double) -> Int {
        guard delta != 0 else { return 0 }
        let sign: CGFloat = delta > 0 ? 1 : -1
        let isNewBurst = lastTime.map { time - $0 > Self.burstGap } ?? true || sign != direction
        lastTime = time
        if isNewBurst {
            direction = sign
            accumulated = 0
            return Int(sign)
        }
        accumulated += abs(delta)
        let threshold = precise ? preciseThreshold : lineThreshold
        guard accumulated >= threshold else { return 0 }
        accumulated -= threshold
        return Int(sign)
    }
}
