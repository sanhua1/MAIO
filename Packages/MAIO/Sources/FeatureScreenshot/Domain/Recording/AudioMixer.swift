import Foundation

/// 把系统声音和麦克风按时间戳对齐后混成一条立体声（ADR-0024）。
/// - 每个来源按"从录制开始算第几个采样"写入，和上一段之间不超过 tolerance 的缝隙或重叠当作连续（时间戳抖动）；
///   更大的缝隙补静音，重叠的部分丢掉；
/// - 所有来源都写到的部分立即混出；某个来源一直没有数据（比如没有声音在播放）时，
///   最多等 latency 个采样，超过就当它是静音，不让另一个来源卡住；
/// - 采样值相加后限制在 -1～1。
struct AudioMixer {
    let channels: Int
    let latency: Int
    let tolerance: Int

    private struct Source {
        /// 缓冲区第一个采样的位置
        var start: Int
        var samples: [[Float]]
        /// 写入过数据（之后的写入才按 tolerance 衔接）
        var started = false

        var end: Int {
            start + (samples.first?.count ?? 0)
        }
    }

    private var sources: [Int: Source] = [:]
    /// 下一个要输出的采样位置
    private(set) var emitted = 0

    /// sources：会有哪些来源。先登记好，某一路的第一段数据晚到时，另一路会等它（最多 latency）
    init(channels: Int = 2, sources: [Int], latency: Int, tolerance: Int) {
        self.channels = channels
        self.latency = latency
        self.tolerance = tolerance
        for id in sources {
            self.sources[id] = Source(start: 0, samples: Array(repeating: [], count: channels))
        }
    }

    /// 写入一段采样。position：这段的第一个采样从录制开始算的位置；samples：每个声道一组，长度相同
    mutating func push(source id: Int, at position: Int, samples: [[Float]]) {
        guard let length = samples.first?.count, length > 0 else { return }
        let input = (0 ..< channels).map { samples[min($0, samples.count - 1)] }
        var source = sources[id] ?? Source(start: max(position, emitted), samples: Array(repeating: [], count: channels))
        var position = position
        if source.started, abs(position - source.end) <= tolerance {
            position = source.end
        }
        // 已经输出过、或者和已有数据重叠的部分丢掉
        let skip = max(0, max(source.end, emitted) - position)
        guard skip < length else {
            sources[id] = source
            return
        }
        let gap = position + skip - source.end
        for channel in 0 ..< channels {
            if gap > 0 {
                source.samples[channel].append(contentsOf: repeatElement(0, count: gap))
            }
            source.samples[channel].append(contentsOf: input[channel][skip...])
        }
        source.started = true
        sources[id] = source
    }

    /// 取出可以输出的混音结果（每个声道一组）；没有时返回 nil。flush：录制结束，全部输出
    mutating func pull(flush: Bool = false) -> [[Float]]? {
        let ends = sources.values.map(\.end)
        guard let latest = ends.max(), let earliest = ends.min() else { return nil }
        let limit = flush ? latest : max(earliest, latest - latency)
        let count = limit - emitted
        guard count > 0 else { return nil }
        var mixed = Array(repeating: [Float](repeating: 0, count: count), count: channels)
        for id in sources.keys {
            guard var source = sources[id] else { continue }
            let offset = source.start - emitted
            let available = min(source.end, limit) - source.start
            if available > 0 {
                for channel in 0 ..< channels {
                    source.samples[channel].withUnsafeBufferPointer { input in
                        for index in 0 ..< available {
                            mixed[channel][offset + index] += input[index]
                        }
                    }
                    source.samples[channel].removeFirst(available)
                }
                source.start += available
            }
            // 这个来源落后于输出位置（一直没数据）：下次写入从输出位置开始
            source.start = max(source.start, limit)
            sources[id] = source
        }
        for channel in 0 ..< channels {
            for index in 0 ..< count {
                mixed[channel][index] = min(1, max(-1, mixed[channel][index]))
            }
        }
        emitted = limit
        return mixed
    }
}
