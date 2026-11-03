/// 长截图的拼接计划（spec 4.6 第 5 条：先记录每一帧用哪些行，最后一次性合成）。
///
/// 不检测吸顶栏和页脚，而是"用新帧的底部一段覆盖画布末尾"（思路参考 Snow Shot 的 compositor，
/// references/snow-apps，GPL，只借鉴思路）：新帧滚动了 shift 行时，取它最后 band 行
/// （band = max(H/2, H/4 + shift)），先从画布末尾去掉 band - shift 行（这些行新帧里也有），再接上。
/// 这样画布末尾始终是最新一帧：高度小于 H/4 的页脚只在最后出现一次；
/// 只写新帧的下半部分，吸顶栏（在顶部）不会重复。
struct StitchPlan: Equatable {
    struct Strip: Equatable {
        /// 第几帧（每次接上的帧依次编号，第一帧是 0）
        var frame: Int
        /// 这一帧里要用的行（像素，左闭右开）
        var start: Int
        var end: Int

        var height: Int {
            end - start
        }
    }

    let frameHeight: Int
    private(set) var strips: [Strip]
    /// 下一帧的编号
    private(set) var nextFrame = 1

    init(frameHeight: Int) {
        self.frameHeight = frameHeight
        strips = [Strip(frame: 0, start: 0, end: frameHeight)]
    }

    var height: Int {
        strips.reduce(0) { $0 + $1.height }
    }

    /// 新帧要用的行
    static func newRows(shift: Int, frameHeight: Int) -> Range<Int> {
        let band = min(frameHeight, max(frameHeight / 2, frameHeight / 4 + shift))
        return (frameHeight - band) ..< frameHeight
    }

    /// 接上滚动了 shift 行的新一帧，返回它的编号
    @discardableResult
    mutating func append(shift: Int) -> Int {
        guard shift > 0 else { return nextFrame - 1 }
        let rows = Self.newRows(shift: shift, frameHeight: frameHeight)
        var overlap = rows.count - shift
        while overlap > 0, let last = strips.indices.last {
            let cut = min(overlap, strips[last].height)
            strips[last].end -= cut
            overlap -= cut
            if strips[last].height == 0 {
                strips.removeLast()
            }
        }
        let frame = nextFrame
        strips.append(Strip(frame: frame, start: rows.lowerBound, end: rows.upperBound))
        nextFrame += 1
        return frame
    }

    /// 还在用的帧
    var usedFrames: Set<Int> {
        Set(strips.map(\.frame))
    }
}
