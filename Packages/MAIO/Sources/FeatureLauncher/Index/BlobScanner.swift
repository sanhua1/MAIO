import Darwin
import Foundation

// 参考：references/oil-find/Sources/COilFind/coilfind.c（sift_scan_entries，MIT）
/// 在首尾相接的名称块里找子串：分段并行，每段用系统的 `memmem`（libc 已经优化过，Debug 版也快）。
/// 名称之间用 0 隔开，查询词里没有 0，所以命中不会跨两个名称。每个名称只记一次。
enum BlobScanner {
    /// 少于这么多条就不分段
    static let minimumPerPart = 65536

    /// 返回命中的条目序号（升序）。`starts` 比条数多一个。
    static func scan(blob: [UInt8], starts: [UInt32], needle: [UInt8]) -> [UInt32] {
        let count = starts.count - 1
        guard count > 0, !needle.isEmpty else { return [] }
        let parts = max(1, min(ProcessInfo.processInfo.activeProcessorCount, count / minimumPerPart))
        let results = PartResults(count: parts)
        blob.withUnsafeBytes { hay in
            starts.withUnsafeBufferPointer { offsets in
                needle.withUnsafeBytes { pattern in
                    let buffers = Buffers(hay: hay, offsets: offsets, needle: pattern)
                    DispatchQueue.concurrentPerform(iterations: parts) { part in
                        let first = count * part / parts
                        let last = count * (part + 1) / parts
                        results[part] = scanPart(buffers.hay, buffers.offsets, buffers.needle, first ..< last)
                    }
                }
            }
        }
        return results.joined
    }

    private static func scanPart(
        _ hay: UnsafeRawBufferPointer, _ offsets: UnsafeBufferPointer<UInt32>, _ needle: UnsafeRawBufferPointer,
        _ entries: Range<Int>,
    ) -> [UInt32] {
        guard let base = hay.baseAddress, let pattern = needle.baseAddress else { return [] }
        var hits: [UInt32] = []
        var entry = entries.lowerBound
        var position = Int(offsets[entry])
        let end = Int(offsets[entries.upperBound])
        while position < end, let found = memmem(base + position, end - position, pattern, needle.count) {
            let offset = UnsafeRawPointer(found) - base
            while Int(offsets[entry + 1]) <= offset {
                entry += 1
            }
            hits.append(UInt32(entry))
            entry += 1
            position = Int(offsets[entry])
        }
        return hits
    }
}

/// 并行时只读的三块内存。它们在 `withUnsafe…` 的作用域里有效，而 `concurrentPerform` 在返回前就结束了所有分段
private struct Buffers: @unchecked Sendable {
    let hay: UnsafeRawBufferPointer
    let offsets: UnsafeBufferPointer<UInt32>
    let needle: UnsafeRawBufferPointer
}

/// 每个分段写自己的格子，全部结束后按顺序拼起来
private final class PartResults: @unchecked Sendable {
    private var parts: [[UInt32]]
    private let lock = NSLock()

    init(count: Int) {
        parts = Array(repeating: [], count: count)
    }

    subscript(index: Int) -> [UInt32] {
        get { lock.withLock { parts[index] } }
        set { lock.withLock { parts[index] = newValue } }
    }

    var joined: [UInt32] {
        lock.withLock { parts.flatMap(\.self) }
    }
}
