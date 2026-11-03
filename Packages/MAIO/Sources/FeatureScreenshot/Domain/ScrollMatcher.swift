import Foundation

/// 灰度帧（逐行存放，每像素 1 字节）。长截图的偏移计算只用灰度，便于用合成数据测试。
struct GrayFrame: Sendable, Equatable {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    subscript(x: Int, y: Int) -> UInt8 {
        pixels[y * width + x]
    }
}

/// 两帧之间的滚动：新的一帧相对上一帧，内容向上移动了 offset 行（像素）
struct ScrollMatch: Equatable {
    var offset: Int
    /// 置信度 0...1：1 - 次佳得分 / 最佳得分。越接近 0 说明有别的位移几乎一样好
    var confidence: Double
    /// 重叠区里有区分度的格子中，对得上的比例
    var inlierRatio: Double
}

/// 长截图的偏移计算（ADR-0014）。思路参考 Snow Shot 的长截图（references/snow-apps，GPL，只借鉴思路）：
/// 只信有区分度的证据、"不动"的内容不参与、严格验收，宁可这一帧不拼也不拼错。
/// 1. 两帧之间几乎不变的列（固定侧栏）和左右边缘（滚动条）不参与；
/// 2. 每行切成 16 个竖条分别哈希。一个格子算"证据"要满足：有明暗变化（不是空白）、
///    哈希在上一帧同一竖条里最多出现 2 次（竖线、分隔线这类到处都一样的不算）、
///    和上一帧同一位置不同（吸顶栏、页脚这些没动的不算）；
/// 3. 哈希相同的证据格子给"行号之差"投票，得票最多的几个位移做完整打分：
///    每个竖条里证据的最长连续匹配段之和；
/// 4. 验收：位移不超过画面高度的 70%、得分够高、至少 4 个竖条有匹配、
///    重叠区证据的匹配比例 ≥ 50%（实验：正确的 ≥ 0.64，错误候选 ≤ 0.25）、和次佳位移拉开差距。
enum ScrollMatcher {
    enum Outcome: Equatable {
        /// 和上一帧一样（没滚动）
        case unchanged
        case moved(ScrollMatch)
        /// 有变化但对不上（滚得太多、往回滚、内容整体变了）
        case unknown
    }

    static let bandCount = 16
    /// 有效格子里最亮和最暗的差至少这么大才算"有内容"
    static let contrast: UInt8 = 24
    /// 哈希在上一帧同一竖条里最多出现这么多次才算有区分度
    static let maximumRepeats = 2
    /// 一帧之间最多滚动画面高度的这个比例，再多就当作对不上（重叠太少，容易误判）
    static let maximumShiftRatio = 0.7
    /// 投票得票最多的这么多个位移才做完整打分
    static let candidateCount = 12
    /// 验收门槛
    static let minimumScore = 20
    static let minimumBands = 4
    static let minimumInlierRatio = 0.5
    static let minimumConfidence = 0.15

    static func match(previous: GrayFrame, current: GrayFrame) -> Outcome {
        guard previous.width == current.width, previous.height == current.height else { return .unknown }
        let columns = changedColumns(previous, current)
        guard columns.count >= 8 else { return .unchanged }
        let bands = split(columns)
        let before = RowCells(previous, bands: bands)
        let after = RowCells(current, bands: bands)
        let index = BandIndex(before)
        let limit = Int(Double(current.height) * maximumShiftRatio) + 1
        var results: [Int: Evidence] = [:]
        for offset in candidates(index: index, after: after, limit: limit) {
            results[offset] = evidence(offset: offset, before: before, after: after, index: index)
        }
        let scores = results.mapValues(\.score)
        guard let offset = best(scores), let found = results[offset] else { return .unknown }
        let confidence = confidence(scores, offset: offset)
        guard found.score >= max(minimumScore, before.bands * 4), found.bands >= min(minimumBands, before.bands),
              found.inlierRatio >= minimumInlierRatio, confidence >= minimumConfidence else { return .unknown }
        return .moved(ScrollMatch(offset: offset, confidence: confidence, inlierRatio: found.inlierRatio))
    }

    /// 得分最高的位移（得分相同取较小的，结果稳定）
    static func best(_ scores: [Int: Int]) -> Int? {
        scores.max { ($0.value, -$0.key) < ($1.value, -$1.key) }?.key
    }

    static func confidence(_ scores: [Int: Int], offset: Int) -> Double {
        guard let best = scores[offset], best > 0 else { return 0 }
        let second = scores.filter { abs($0.key - offset) > 2 }.values.max() ?? 0
        return 1 - Double(second) / Double(best)
    }

    // MARK: 证据

    struct Evidence {
        /// 各竖条最长连续匹配段之和
        var score = 0
        var inliers = 0
        var outliers = 0
        /// 有匹配的竖条数
        var bands = 0

        var inlierRatio: Double {
            inliers + outliers > 0 ? Double(inliers) / Double(inliers + outliers) : 0
        }
    }

    /// 位移 offset 下的证据：新帧第 row 行对应上一帧第 row + offset 行
    static func evidence(offset: Int, before: RowCells, after: RowCells, index: BandIndex) -> Evidence {
        var result = Evidence()
        let end = after.height - offset
        guard end > 0 else { return result }
        for band in 0 ..< before.bands {
            var run = 0
            var longest = 0
            var matched = false
            for row in 0 ..< end where index.isEvidence(after, band, row) {
                if after.hash(band, row) == before.hash(band, row + offset) {
                    result.inliers += 1
                    run += 1
                    longest = max(longest, run)
                    matched = true
                } else {
                    result.outliers += 1
                    run = 0
                }
            }
            result.score += longest
            result.bands += matched ? 1 : 0
        }
        return result
    }

    /// 投票：哈希相同的证据格子给"行号之差"投一票，返回得票最多的位移
    static func candidates(index: BandIndex, after: RowCells, limit: Int) -> Set<Int> {
        var votes = [Int](repeating: 0, count: max(limit, 1))
        for band in 0 ..< after.bands {
            for row in 0 ..< after.height where index.isEvidence(after, band, row) {
                for match in index.rows(band, after.hash(band, row)) where match - row >= 1 && match - row < limit {
                    votes[match - row] += 1
                }
            }
        }
        let ranked = votes.indices.filter { votes[$0] > 0 }.sorted { votes[$0] > votes[$1] }
        return Set(ranked.prefix(candidateCount))
    }

    // MARK: 列

    /// 参与比较的列：去掉左右边缘（滚动条），以及两帧之间几乎完全不变的列（隔行抽样）
    static func changedColumns(_ first: GrayFrame, _ second: GrayFrame) -> [Int] {
        let width = first.width
        let height = first.height
        let margin = min(max(20, width / 20), width / 4)
        var same = [Int](repeating: 0, count: width)
        first.pixels.withUnsafeBufferPointer { lhs in
            second.pixels.withUnsafeBufferPointer { rhs in
                same.withUnsafeMutableBufferPointer { counts in
                    var y = 0
                    while y < height {
                        let base = y * width
                        var x = margin
                        while x < width - margin {
                            if lhs[base + x] == rhs[base + x] {
                                counts[x] += 1
                            }
                            x += 1
                        }
                        y += 2
                    }
                }
            }
        }
        let required = Double((height + 1) / 2) * 0.98
        return (margin ..< max(margin, width - margin)).filter { Double(same[$0]) < required }
    }

    /// 分成竖条；每条只取一半的列（隔列抽样，速度翻倍，实验里不影响准确度）
    static func split(_ columns: [Int]) -> [[Int]] {
        let size = max(1, (columns.count + bandCount - 1) / bandCount)
        return stride(from: 0, to: columns.count, by: size).map { start in
            Array(stride(from: start, to: min(start + size, columns.count), by: 2).map { columns[$0] })
        }
    }
}

/// 上一帧每个竖条的"哈希 → 行号"索引，用来判断格子有没有区分度
struct BandIndex {
    private let before: RowCells
    private var rowsByHash: [[UInt64: [Int]]]

    init(_ before: RowCells) {
        self.before = before
        rowsByHash = (0 ..< before.bands).map { band in
            var map: [UInt64: [Int]] = [:]
            for row in 0 ..< before.height where before.isInformative(band, row) {
                map[before.hash(band, row), default: []].append(row)
            }
            return map
        }
    }

    func rows(_ band: Int, _ hash: UInt64) -> [Int] {
        let rows = rowsByHash[band][hash] ?? []
        return rows.count <= ScrollMatcher.maximumRepeats ? rows : []
    }

    /// 新帧的这个格子能不能当证据：有内容、在上一帧里不常见、和上一帧同一位置不同（不是没动的部分）
    func isEvidence(_ after: RowCells, _ band: Int, _ row: Int) -> Bool {
        guard after.isInformative(band, row) else { return false }
        let hash = after.hash(band, row)
        guard hash != before.hash(band, row) else { return false }
        return (rowsByHash[band][hash]?.count ?? 0) <= ScrollMatcher.maximumRepeats
    }
}

/// 每行每个竖条的哈希和"有没有内容"（平铺存放：竖条 × 行）
struct RowCells {
    let bands: Int
    let height: Int
    private(set) var hashes: [UInt64]
    private(set) var informative: [Bool]

    private static let basis: UInt64 = 14_695_981_039_346_656_037
    private static let prime: UInt64 = 1_099_511_628_211

    func hash(_ band: Int, _ row: Int) -> UInt64 {
        hashes[band * height + row]
    }

    func isInformative(_ band: Int, _ row: Int) -> Bool {
        informative[band * height + row]
    }

    init(_ frame: GrayFrame, bands columns: [[Int]]) {
        bands = columns.count
        height = frame.height
        var hashes = [UInt64](repeating: 0, count: columns.count * frame.height)
        var informative = [Bool](repeating: false, count: columns.count * frame.height)
        let width = frame.width
        let height = frame.height
        frame.pixels.withUnsafeBufferPointer { pixels in
            for (band, bandColumns) in columns.enumerated() {
                bandColumns.withUnsafeBufferPointer { xs in
                    for y in 0 ..< height {
                        var hash = Self.basis
                        var low: UInt8 = 255
                        var high: UInt8 = 0
                        let base = y * width
                        for x in xs {
                            let value = pixels[base + x]
                            hash = (hash ^ UInt64(value)) &* Self.prime
                            low = min(low, value)
                            high = max(high, value)
                        }
                        hashes[band * height + y] = hash
                        informative[band * height + y] = high &- low > ScrollMatcher.contrast
                    }
                }
            }
        }
        self.hashes = hashes
        self.informative = informative
    }
}
