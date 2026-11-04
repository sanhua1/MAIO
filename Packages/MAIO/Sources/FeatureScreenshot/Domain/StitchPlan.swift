/// 长截图的拼接计划（ADR-0014 修订三）。
///
/// 显式维护"当前画面顶部在画布中的位置"，按**绝对位置**写入新帧露出的部分，
/// 而不是"往画布末尾追加"。这样：
/// - 正常往下滚只写新帧靠下的一段（重叠部分被覆盖，不会重复）；
/// - 往回滚时只更新位置、不写图；滚过起点才真正向画布头部扩展；
/// - 匹配成功就更新位置，所以往回滚之后能立刻接着拼。
struct StitchPlan: Equatable {
    struct Strip: Equatable {
        /// 第几帧（每次真正写入画布的帧依次编号）
        var frame: Int
        /// 这一帧里要用的行（像素，左闭右开）
        var start: Int
        var end: Int
        /// 这段行在画布上的起始行
        var top: Int

        var height: Int {
            end - start
        }
    }

    /// 一次写入的结果
    enum Placement: Equatable {
        /// 新帧完全落在已拼范围里：画布不动，只更新位置
        case inside
        /// 需要帧里的这些行（帧内坐标）
        case written(Range<Int>)
    }

    let frameHeight: Int
    private(set) var strips: [Strip] = []
    private(set) var canvasHeight = 0
    /// 最新一帧顶部在画布中的位置（画布已经向下平移过，所以不会是负数）
    private(set) var position = 0

    /// 第一帧：铺满画布
    mutating func begin(frame: Int = 0) {
        strips = [Strip(frame: frame, start: 0, end: frameHeight, top: 0)]
        canvasHeight = frameHeight
        position = 0
    }

    /// 接上滚动了 offset 行的新一帧（正数 = 往下滚），返回需要写进画布的部分
    @discardableResult
    mutating func append(frame: Int, offset: Int) -> Placement {
        let rawTop = position + offset
        if rawTop < 0 {
            // 往回滚超过了画布开头：画布整体下移，新露出的头部由这一帧的上半帧补上
            let exposed = -rawTop
            shift(by: exposed)
            let end = min(frameHeight, max(exposed, frameHeight / 2))
            return write(0 ..< end, frame: frame, top: 0)
        }
        let bottom = rawTop + frameHeight
        if bottom <= canvasHeight {
            position = rawTop
            return .inside
        }
        // 往下滚：只写新帧靠下的一段。band 随位移变大而变大，保证：
        // - 至少覆盖新露出的内容（不会留缝）；
        // - 往前多覆盖最多半帧，把上一帧临时写下的页脚盖掉；
        // - 顶部留出至少 1/4 帧，正常的吸顶栏不会被写进画布中间。
        let shift = offset
        let band = min(frameHeight, max(frameHeight / 2, frameHeight / 4 + shift))
        let start = frameHeight - band
        return write((rawTop + start) ..< bottom, frame: frame, top: rawTop)
    }

    /// 还在用的帧
    var usedFrames: Set<Int> {
        Set(strips.map(\.frame))
    }

    // MARK: 画布操作

    private mutating func write(_ range: Range<Int>, frame: Int, top: Int) -> Placement {
        let from = max(range.lowerBound, top)
        let to = min(range.upperBound, top + frameHeight)
        guard from < to else {
            position = max(0, top)
            return .inside
        }
        overwrite(from ..< to, frame: frame, top: top)
        canvasHeight = max(canvasHeight, top + frameHeight)
        position = max(0, top)
        return .written((from - top) ..< (to - top))
    }

    /// 用新段覆盖画布上的 range，断开的旧段裁剪后保留
    private mutating func overwrite(_ range: Range<Int>, frame: Int, top: Int) {
        var kept: [Strip] = []
        for strip in strips {
            let lower = strip.top
            let upper = strip.top + strip.height
            if upper <= range.lowerBound || lower >= range.upperBound {
                kept.append(strip)
                continue
            }
            if lower < range.lowerBound {
                var head = strip
                head.end = strip.start + (range.lowerBound - lower)
                kept.append(head)
            }
            if upper > range.upperBound {
                var tail = strip
                let cut = range.upperBound - lower
                tail.start = strip.start + cut
                tail.top = range.upperBound
                kept.append(tail)
            }
        }
        let start = max(range.lowerBound, top)
        let end = min(range.upperBound, top + frameHeight)
        if start < end {
            kept.append(Strip(frame: frame, start: start - top, end: end - top, top: start))
        }
        kept.sort { $0.top < $1.top }
        strips = kept
    }

    private mutating func shift(by amount: Int) {
        strips = strips.map { strip in
            var moved = strip
            moved.top += amount
            return moved
        }
        canvasHeight += amount
        position += amount
    }
}
