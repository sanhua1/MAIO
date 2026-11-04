import Foundation

/// 灰度帧（逐行存放，每像素 1 字节）。长截图的偏移计算只用灰度，便于用合成数据测试。
struct GrayFrame: Sendable, Equatable {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    subscript(x: Int, y: Int) -> UInt8 {
        pixels[y * width + x]
    }

    /// 只按列抽样（高度不变）。竖直位移估计不依赖每一列，抽样比块平均便宜得多。
    func sampled(width targetWidth: Int) -> GrayFrame {
        let targetWidth = max(1, min(targetWidth, width))
        guard targetWidth != width else { return self }
        let columns = (0 ..< targetWidth).map { $0 * width / targetWidth }
        var output = [UInt8](repeating: 0, count: targetWidth * height)
        pixels.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                for y in 0 ..< height {
                    let sourceRow = y * width
                    let targetRow = y * targetWidth
                    var x = 0
                    while x < targetWidth {
                        destination[targetRow + x] = source[sourceRow + columns[x]]
                        x += 1
                    }
                }
            }
        }
        return GrayFrame(width: targetWidth, height: height, pixels: output)
    }

    /// 块平均缩小（最近邻会让细线忽隐忽现，块平均更稳）。
    /// 宽高各自按需缩放，一个目标像素取原图对应方块的平均值。
    func reduced(width targetWidth: Int, height targetHeight: Int) -> GrayFrame {
        let targetWidth = max(1, min(targetWidth, width))
        let targetHeight = max(1, min(targetHeight, height))
        guard targetWidth != width || targetHeight != height else { return self }
        // 方块边界只算一次：Debug 下每个除法都很贵，不能放进逐像素的循环里
        let xs = (0 ... targetWidth).map { $0 * width / targetWidth }
        let ys = (0 ... targetHeight).map { $0 * height / targetHeight }
        var output = [UInt8](repeating: 0, count: targetWidth * targetHeight)
        pixels.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                for ty in 0 ..< targetHeight {
                    let y0 = ys[ty]
                    let y1 = max(y0 + 1, ys[ty + 1])
                    for tx in 0 ..< targetWidth {
                        let x0 = xs[tx]
                        let x1 = max(x0 + 1, xs[tx + 1])
                        var sum = 0
                        for y in y0 ..< y1 {
                            let base = y * width
                            var x = x0
                            while x < x1 {
                                sum += Int(source[base + x])
                                x += 1
                            }
                        }
                        destination[ty * targetWidth + tx] = UInt8(sum / ((y1 - y0) * (x1 - x0)))
                    }
                }
            }
        }
        return GrayFrame(width: targetWidth, height: targetHeight, pixels: output)
    }
}
