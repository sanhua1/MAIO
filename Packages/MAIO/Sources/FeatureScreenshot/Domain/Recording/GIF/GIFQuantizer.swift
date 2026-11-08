import Foundation

/// 调色板 + 每个像素的索引
struct GIFIndexedImage: Equatable, Sendable {
    /// 0xRRGGBB，最多 256 个
    var palette: [UInt32]
    /// 透明色在调色板里的位置（"和上一帧一样"的像素）
    var transparentIndex: Int?
    var indices: [UInt8]
}

/// 把一块像素（0xAARRGGBB；值为 0 表示透明）转成最多 256 色。
/// - 颜色不超过 256 种时（界面、文字截图大多如此）直接用原色，完全无损；
/// - 否则在 15 位（每通道 5 位）直方图上做中位切分，像素按所在格子映射，不抖动
///   （屏幕内容抖动后满屏噪点，文件也大很多）。
enum GIFQuantizer {
    static let transparent: UInt32 = 0

    static func quantize(_ pixels: [UInt32]) -> GIFIndexedImage {
        pixels.withUnsafeBufferPointer { buffer in
            exactPalette(buffer) ?? medianCut(buffer)
        }
    }

    // MARK: 原色

    /// 用一张 1024 格的开放寻址表数颜色，超过 256 种就放弃。连续相同的像素直接复用上一个结果
    private static func exactPalette(_ pixels: UnsafeBufferPointer<UInt32>) -> GIFIndexedImage? {
        let capacity = 1024
        var keys = [UInt32](repeating: 0, count: capacity)
        var slots = [UInt8](repeating: 0, count: capacity)
        var palette: [UInt32] = []
        var transparentIndex: Int?
        var indices = [UInt8](repeating: 0, count: pixels.count)
        var last: UInt32 = 1
        var lastIndex: UInt8 = 0
        for (position, pixel) in pixels.enumerated() {
            if pixel == last {
                indices[position] = lastIndex
                continue
            }
            // 透明像素的值是 0，和空格子冲突，存表时换成一个不会出现的值（不透明像素的 alpha 都是 FF）
            let key = pixel == transparent ? 0x0100_0000 : pixel
            var slot = Int((key &* 2_654_435_761) >> 22)
            while keys[slot] != 0, keys[slot] != key {
                slot = (slot + 1) & (capacity - 1)
            }
            if keys[slot] == 0 {
                guard palette.count < 256 else { return nil }
                keys[slot] = key
                slots[slot] = UInt8(palette.count)
                if pixel == transparent {
                    transparentIndex = palette.count
                }
                palette.append(pixel & 0xFFFFFF)
            }
            last = pixel
            lastIndex = slots[slot]
            indices[position] = lastIndex
        }
        return GIFIndexedImage(palette: palette, transparentIndex: transparentIndex, indices: indices)
    }

    // MARK: 中位切分

    private struct Histogram {
        var counts = [Int](repeating: 0, count: 32768)
        var red = [Int](repeating: 0, count: 32768)
        var green = [Int](repeating: 0, count: 32768)
        var blue = [Int](repeating: 0, count: 32768)
        var opaqueCount = 0

        var hasTransparent: Bool {
            opaqueCount != total
        }

        private var total = 0

        static func bin(_ pixel: UInt32) -> Int {
            Int((pixel >> 9) & 0x7C00 | (pixel >> 6) & 0x03E0 | (pixel >> 3) & 0x001F)
        }

        init(_ pixels: UnsafeBufferPointer<UInt32>) {
            total = pixels.count
            for pixel in pixels {
                if pixel == GIFQuantizer.transparent {
                    continue
                }
                opaqueCount += 1
                let bin = Self.bin(pixel)
                counts[bin] += 1
                red[bin] += Int((pixel >> 16) & 0xFF)
                green[bin] += Int((pixel >> 8) & 0xFF)
                blue[bin] += Int(pixel & 0xFF)
            }
        }
    }

    /// 一个切分盒：bins[start..<end]
    private struct Box {
        var start: Int
        var end: Int
        var population: Int
    }

    private static func medianCut(_ pixels: UnsafeBufferPointer<UInt32>) -> GIFIndexedImage {
        let histogram = Histogram(pixels)
        var bins = (0 ..< 32768).filter { histogram.counts[$0] > 0 }
        let budget = histogram.hasTransparent ? 255 : 256
        var boxes = [Box(start: 0, end: bins.count, population: histogram.opaqueCount)]
        while boxes.count < budget {
            // 拆像素最多、而且还能拆的盒子
            guard let target = boxes.indices.filter({ boxes[$0].end - boxes[$0].start > 1 })
                .max(by: { boxes[$0].population < boxes[$1].population }) else { break }
            let (left, right) = split(boxes[target], bins: &bins, counts: histogram.counts)
            boxes[target] = left
            boxes.append(right)
        }
        var palette: [UInt32] = []
        var lookup = [UInt8](repeating: 0, count: 32768)
        for (index, box) in boxes.enumerated() {
            var count = 0, red = 0, green = 0, blue = 0
            for bin in bins[box.start ..< box.end] {
                count += histogram.counts[bin]
                red += histogram.red[bin]
                green += histogram.green[bin]
                blue += histogram.blue[bin]
                lookup[bin] = UInt8(index)
            }
            let divisor = max(count, 1)
            palette.append(UInt32(red / divisor) << 16 | UInt32(green / divisor) << 8 | UInt32(blue / divisor))
        }
        var transparentIndex: Int?
        if histogram.hasTransparent {
            transparentIndex = palette.count
            palette.append(0)
        }
        let transparentSlot = UInt8(transparentIndex ?? 0)
        let indices = pixels.map { pixel in
            pixel == transparent ? transparentSlot : lookup[Histogram.bin(pixel)]
        }
        return GIFIndexedImage(palette: palette, transparentIndex: transparentIndex, indices: indices)
    }

    /// 沿跨度最大的通道排序，在像素数的中位处切开
    private static func split(_ box: Box, bins: inout [Int], counts: [Int]) -> (Box, Box) {
        var low = [31, 31, 31], high = [0, 0, 0]
        for bin in bins[box.start ..< box.end] {
            for channel in 0 ..< 3 {
                let value = (bin >> (10 - channel * 5)) & 31
                low[channel] = min(low[channel], value)
                high[channel] = max(high[channel], value)
            }
        }
        let spans = (0 ..< 3).map { high[$0] - low[$0] }
        let channel = spans.indices.max { spans[$0] < spans[$1] } ?? 0
        let shift = 10 - channel * 5
        bins[box.start ..< box.end].sort { ($0 >> shift) & 31 < ($1 >> shift) & 31 }
        var running = 0
        var cut = box.start + 1
        for position in box.start ..< box.end - 1 {
            running += counts[bins[position]]
            cut = position + 1
            if running * 2 >= box.population {
                break
            }
        }
        return (
            Box(start: box.start, end: cut, population: running),
            Box(start: cut, end: box.end, population: box.population - running),
        )
    }
}
