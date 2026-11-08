import Foundation

/// 编码好的一帧：画面上变化的那块区域
struct GIFFrame: Equatable, Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    let palette: [UInt32]
    let transparentIndex: Int?
    let minimumCodeSize: Int
    /// LZW 码流（还没分成 255 字节的小块）
    let data: [UInt8]
}

/// 边录边编的 GIF 帧编码：只编码和上一帧不同的最小矩形，矩形里没变的像素记成透明（显示上一帧），
/// 静止的界面几乎不占空间。像素格式是 0xAARRGGBB（BGRA 小端读成 UInt32），行优先、没有行尾填充。
struct GIFFrameEncoder {
    struct Rect: Equatable {
        var x: Int
        var y: Int
        var width: Int
        var height: Int
    }

    let width: Int
    let height: Int
    private var previous: [UInt32] = []

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// 画面和上一帧完全相同时返回 nil（上一帧的显示时间顺延）
    mutating func encode(_ pixels: [UInt32]) -> GIFFrame? {
        guard pixels.count == width * height, width > 0, height > 0 else { return nil }
        let rect: Rect
        let region: [UInt32]
        if previous.isEmpty {
            rect = Rect(x: 0, y: 0, width: width, height: height)
            // 第一帧没有可以透出来的内容；值为 0 的像素（理论上不会出现）改成不透明的黑色
            region = pixels.map { $0 == GIFQuantizer.transparent ? 0xFF00_0000 : $0 }
        } else {
            guard let changed = Self.changedRect(previous, pixels, width: width, height: height) else { return nil }
            rect = changed
            region = Self.extract(pixels, previous: previous, rect: changed, width: width)
        }
        previous = pixels
        let indexed = GIFQuantizer.quantize(region)
        let codeSize = max(2, GIFFormat.paletteBits(indexed.palette.count))
        return GIFFrame(
            x: rect.x, y: rect.y, width: rect.width, height: rect.height,
            palette: indexed.palette, transparentIndex: indexed.transparentIndex, minimumCodeSize: codeSize,
            data: GIFLZW.encode(indexed.indices, minimumCodeSize: codeSize),
        )
    }

    /// 两帧不同的最小矩形：先按行用 memcmp 找上下边界，再在这些行里找左右边界
    static func changedRect(_ old: [UInt32], _ new: [UInt32], width: Int, height: Int) -> Rect? {
        old.withUnsafeBufferPointer { old in
            new.withUnsafeBufferPointer { new in
                guard let oldBase = old.baseAddress, let newBase = new.baseAddress else { return nil }
                let rowBytes = width * MemoryLayout<UInt32>.size
                func rowDiffers(_ row: Int) -> Bool {
                    memcmp(oldBase + row * width, newBase + row * width, rowBytes) != 0
                }
                guard let top = (0 ..< height).first(where: rowDiffers),
                      let bottom = (top ..< height).reversed().first(where: rowDiffers) else { return nil }
                var left = width, right = -1
                for row in top ... bottom {
                    let start = row * width
                    var column = 0
                    while column < left, old[start + column] == new[start + column] {
                        column += 1
                    }
                    left = min(left, column)
                    column = width - 1
                    while column > right, old[start + column] == new[start + column] {
                        column -= 1
                    }
                    right = max(right, column)
                }
                guard right >= left else { return nil }
                return Rect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
            }
        }
    }

    /// 取出矩形里的像素；和上一帧相同的记为透明
    private static func extract(_ pixels: [UInt32], previous: [UInt32], rect: Rect, width: Int) -> [UInt32] {
        var region = [UInt32](repeating: GIFQuantizer.transparent, count: rect.width * rect.height)
        var target = 0
        for row in rect.y ..< rect.y + rect.height {
            let start = row * width + rect.x
            for column in start ..< start + rect.width {
                let pixel = pixels[column]
                if pixel != previous[column] {
                    region[target] = pixel == GIFQuantizer.transparent ? 0xFF00_0000 : pixel
                }
                target += 1
            }
        }
        return region
    }
}

/// GIF89a 文件的各个部分
enum GIFFormat {
    /// 文件头 + 逻辑屏幕（不用全局调色板，每帧自带）+ 无限循环
    static func header(width: Int, height: Int) -> Data {
        var data = Data("GIF89a".utf8)
        data.appendLittleEndian(UInt16(clamping: width))
        data.appendLittleEndian(UInt16(clamping: height))
        data.append(contentsOf: [0x00, 0x00, 0x00])
        data.append(contentsOf: [0x21, 0xFF, 0x0B])
        data.append(contentsOf: Array("NETSCAPE2.0".utf8))
        data.append(contentsOf: [0x03, 0x01, 0x00, 0x00, 0x00])
        return data
    }

    /// 一帧：图形控制扩展（显示时长、透明色、保留上一帧）+ 图像描述 + 局部调色板 + LZW 数据块
    static func frame(_ frame: GIFFrame, delay centiseconds: Int) -> Data {
        var data = Data()
        let transparent = frame.transparentIndex
        // 处置方式 1：不清除，下一帧的透明像素透出这一帧
        data.append(contentsOf: [0x21, 0xF9, 0x04, UInt8(1 << 2 | (transparent == nil ? 0 : 1))])
        data.appendLittleEndian(UInt16(clamping: centiseconds))
        data.append(contentsOf: [UInt8(transparent ?? 0), 0x00])
        data.append(0x2C)
        for value in [frame.x, frame.y, frame.width, frame.height] {
            data.appendLittleEndian(UInt16(clamping: value))
        }
        let bits = paletteBits(frame.palette.count)
        data.append(0x80 | UInt8(bits - 1))
        for slot in 0 ..< 1 << bits {
            let color = slot < frame.palette.count ? frame.palette[slot] : 0
            data.append(contentsOf: [UInt8(color >> 16 & 0xFF), UInt8(color >> 8 & 0xFF), UInt8(color & 0xFF)])
        }
        data.append(UInt8(frame.minimumCodeSize))
        var offset = 0
        while offset < frame.data.count {
            let length = min(255, frame.data.count - offset)
            data.append(UInt8(length))
            data.append(contentsOf: frame.data[offset ..< offset + length])
            offset += length
        }
        data.append(0x00)
        return data
    }

    static let trailer = Data([0x3B])

    /// 调色板要补齐到 2 的幂：返回位数（1～8）
    static func paletteBits(_ count: Int) -> Int {
        var bits = 1
        while 1 << bits < count, bits < 8 {
            bits += 1
        }
        return bits
    }

    /// 帧的显示时长（1/100 秒）：按绝对时间取整再相减，不会累积误差；至少 2（更小的值很多播放器当成 10）
    static func delay(from start: Double, to end: Double) -> Int {
        max(2, Int((end * 100).rounded()) - Int((start * 100).rounded()))
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }
}
