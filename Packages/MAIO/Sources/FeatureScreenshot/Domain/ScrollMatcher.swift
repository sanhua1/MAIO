import Foundation

/// 两帧之间的滚动：新的一帧相对上一帧，内容向上移动了 offset 行（像素，带符号）。
struct ScrollMatch: Equatable {
    /// 正数 = 用户往下滚（内容向上移动）；负数 = 往回滚
    var offset: Int
    /// 重叠区变化像素里对不上的比例（0 最好）
    var mismatch: Double
}

/// 长截图的偏移计算（ADR-0014 修订三）。
///
/// 参考成熟的滚动拼接做法（容差比较 + 只比较变化内容 + 全偏移搜索 + 分层 + 严格验收）：
/// 1. **容差比较**：两帧像素差超过 `tolerance` 才算"变了"/"对不上"，抗亚像素滚动、
///    抗锯齿和轻微动画；不再要求逐像素完全相等；
/// 2. **只比较变化过的像素**：固定页眉、侧栏、空白不参与，也不会被误当成匹配；
/// 3. **全偏移搜索**：负、正两个方向都搜（±70% 画面高度），不会因为"候选没进前几名"漏掉正确位移；
/// 4. **分层降采样**：粗层（块平均到 64×128）全搜取出几个候选，再在精层（宽度抽样到 ≤512）细化，
///    兼顾速度与 1 像素精度；
/// 5. **严格验收**：最佳位移的不匹配率 ≤ 30%，且必须和次佳（相差 3 行以上）拉开差距。
enum ScrollMatcher {
    enum Outcome: Equatable {
        /// 和上一帧一样（没滚动，或只有很小的局部变化）
        case unchanged
        case moved(ScrollMatch)
        /// 有变化但对不上（滚得太多、页面自己变了、内容重复分不清方向）
        case unknown
    }

    /// 一帧之间最多滚动画面高度的这个比例（重叠至少 30%）
    static let maximumShiftRatio = 0.7
    /// 像素差超过这么多才算"变了"/"对不上"
    static let tolerance = 10
    /// 差异像素少于总量的这个比例就当作没动（光标闪烁、小动画）
    static let stillRatio = 0.005
    /// 验收：最佳位移的不匹配率上限
    static let maximumMismatch = 0.30
    /// 次佳位移（相差 3 行以上）必须比最佳差这么多，否则算分不清
    static let minimumMargin = 0.03

    // 分层搜索的参数
    static let coarseWidth = 64
    static let coarseHeight = 128
    static let coarseCandidates = 4
    static let fineWidth = 512
    static let fineStride = 4
    /// 粗层换算成原始坐标后可能有 1～2 像素误差，细化时向两边各多搜几行
    static let refineSlack = 2

    static func match(previous: GrayFrame, current: GrayFrame) -> Outcome {
        guard previous.width == current.width, previous.height == current.height,
              previous.width > 3, previous.height > 3 else { return .unknown }
        let limit = min(previous.height - 1, Int(Double(previous.height) * maximumShiftRatio))
        guard limit >= 1 else { return .unknown }
        // 匹配统一在"宽度抽样到 ≤ 512、高度不变"的精层上做（压缩宽度不影响竖直位移）
        let width = min(previous.width, fineWidth)
        let prev = previous.sampled(width: width)
        let cur = current.sampled(width: width)
        let difference = Difference(prev, cur)
        guard difference.pixels >= max(64, prev.pixels.count / 200) else { return .unchanged }
        let candidates = coarseCandidates(prev, cur, limit: limit)
        let matches = refine(prev, cur, difference: difference, candidates: candidates, limit: limit)
        return verdict(matches, limit: limit)
    }

    // MARK: 分层搜索

    private struct Candidates {
        /// 换算成原始坐标的候选位移
        var offsets: [Int]
        /// 粗层换算的取整误差（原始行数）
        var slack: Int
    }

    /// 粗层降采样后全偏移搜索，返回换算成原始坐标的几个候选
    private static func coarseCandidates(_ previous: GrayFrame, _ current: GrayFrame, limit: Int) -> Candidates {
        let scale = max(1, previous.height / coarseHeight)
        let width = min(previous.width, coarseWidth)
        let prev = previous.reduced(width: width, height: max(1, previous.height / scale))
        let cur = current.reduced(width: width, height: max(1, current.height / scale))
        let coarseLimit = max(1, limit / scale)
        let difference = Difference(prev, cur)
        var scored: [(offset: Int, score: Double)] = []
        for offset in -coarseLimit ... coarseLimit where offset != 0 {
            scored.append((offset, mismatch(prev, cur, difference: difference, offset: offset, stride: 1)))
        }
        scored.sort { ($0.score, abs($0.offset)) < ($1.score, abs($1.offset)) }
        // 块平均时实际行数是整除的，换算回原始坐标可能差一个粗行
        let slack = refineSlack + previous.height / max(1, prev.height)
        var result: [Int] = []
        for item in scored where result.allSatisfy({ abs($0 - item.offset * scale) > scale * 2 }) {
            result.append(item.offset * scale)
            if result.count == coarseCandidates {
                break
            }
        }
        return Candidates(offsets: result, slack: slack)
    }

    /// 在候选附近用全分辨率（宽度已经降到 512）逐像素细化
    private static func refine(
        _ previous: GrayFrame, _ current: GrayFrame, difference: Difference,
        candidates: Candidates, limit: Int,
    ) -> [(offset: Int, mismatch: Double)] {
        var results: [(offset: Int, mismatch: Double)] = []
        for candidate in candidates.offsets {
            let from = max(-limit, candidate - candidates.slack)
            let to = min(limit, candidate + candidates.slack)
            for offset in from ... to {
                results.append((offset, mismatch(previous, current, difference: difference, offset: offset, stride: fineStride)))
            }
        }
        return results
    }

    /// 位移 offset 下，重叠区变化像素里对不上的比例。stride 隔行/隔列抽样。
    private static func mismatch(
        _ previous: GrayFrame, _ current: GrayFrame, difference: Difference, offset: Int, stride: Int,
    ) -> Double {
        let start = max(0, -offset)
        let end = min(current.height, current.height - offset)
        guard end - start >= 2 else { return 1 }
        let width = current.width
        let tolerance = ScrollMatcher.tolerance
        var total = 0
        var bad = 0
        previous.pixels.withUnsafeBufferPointer { head in
            current.pixels.withUnsafeBufferPointer { tail in
                difference.mask.withUnsafeBufferPointer { mask in
                    difference.rows.withUnsafeBufferPointer { rows in
                        var y = start
                        while y < end {
                            // 两帧这一行都没有变化时整行跳过（固定页眉、侧栏、空白）
                            if rows[y] || rows[y + offset] {
                                let here = y * width
                                let there = (y + offset) * width
                                var x = 0
                                while x < width {
                                    if mask[here + x] || mask[there + x] {
                                        total += 1
                                        let delta = Int(tail[here + x]) - Int(head[there + x])
                                        if delta > tolerance || delta < -tolerance {
                                            bad += 1
                                        }
                                    }
                                    x += stride
                                }
                            }
                            y += stride
                        }
                    }
                }
            }
        }
        return total > 0 ? Double(bad) / Double(total) : 1
    }

    // MARK: 验收

    private static func verdict(_ matches: [(offset: Int, mismatch: Double)], limit: Int) -> Outcome {
        guard let best = matches.min(by: {
            ($0.mismatch, abs($0.offset)) < ($1.mismatch, abs($1.offset))
        }) else { return .unknown }
        guard best.offset != 0 else { return .unchanged }
        guard best.mismatch <= maximumMismatch, abs(best.offset) < limit else { return .unknown }
        let second = matches.filter { abs($0.offset - best.offset) > 2 }.map(\.mismatch).min()
        if let second, second - best.mismatch < minimumMargin {
            return .unknown
        }
        return .moved(ScrollMatch(offset: best.offset, mismatch: best.mismatch))
    }
}

/// 两帧同位比较：哪些像素/行有变化、一共有多少像素变了。
/// 只比较"有变化"的像素，固定页眉、侧栏、空白既不算证据也不会拉低匹配率。
struct Difference {
    private(set) var mask: [Bool]
    private(set) var rows: [Bool]
    private(set) var pixels = 0

    init(_ first: GrayFrame, _ second: GrayFrame) {
        rows = [Bool](repeating: false, count: first.height)
        mask = [Bool](repeating: false, count: first.width * first.height)
        guard first.width == second.width, first.height == second.height else { return }
        let width = first.width
        let tolerance = ScrollMatcher.tolerance
        var changedPixels = 0
        first.pixels.withUnsafeBufferPointer { a in
            second.pixels.withUnsafeBufferPointer { b in
                mask.withUnsafeMutableBufferPointer { mask in
                    rows.withUnsafeMutableBufferPointer { rows in
                        for y in 0 ..< first.height {
                            let base = y * width
                            var changed = false
                            var x = 0
                            while x < width {
                                let delta = Int(a[base + x]) - Int(b[base + x])
                                if delta > tolerance || delta < -tolerance {
                                    mask[base + x] = true
                                    changed = true
                                    changedPixels += 1
                                }
                                x += 1
                            }
                            rows[y] = changed
                        }
                    }
                }
            }
        }
        pixels = changedPixels
    }
}
