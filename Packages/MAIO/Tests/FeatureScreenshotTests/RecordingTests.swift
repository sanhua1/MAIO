import CoreGraphics
@testable import FeatureScreenshot
import Foundation
import ImageIO
import Testing

/// 用系统 ImageIO 解码我们写出的 GIF：每帧都是合成后的整幅画面（0xFFRRGGBB）
private func decodeGIF(_ data: Data) -> [[UInt32]] {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return [] }
    return (0 ..< CGImageSourceGetCount(source)).compactMap { index in
        guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { return nil }
        var pixels = [UInt32](repeating: 0, count: image.width * image.height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue,
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return drawn ? pixels : nil
    }
}

private struct Random {
    var state: UInt64

    mutating func next(_ bound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 33) % UInt64(bound))
    }
}

/// 写一个完整的 GIF（每帧 10/100 秒）
private func makeGIF(_ frames: [[UInt32]], width: Int, height: Int) -> Data {
    var encoder = GIFFrameEncoder(width: width, height: height)
    var data = GIFFormat.header(width: width, height: height)
    for (index, pixels) in frames.enumerated() {
        if let frame = encoder.encode(pixels) {
            data.append(GIFFormat.frame(frame, delay: 10 + index))
        }
    }
    data.append(GIFFormat.trailer)
    return data
}

struct GIFEncodingTests {
    @Test func `颜色不超过 256 种时完全无损，变化区域外的像素透出上一帧`() {
        let width = 97, height = 61
        var random = Random(state: 1)
        let colors = (0 ..< 200).map { _ in 0xFF00_0000 | UInt32(random.next(1 << 24)) }
        let first = (0 ..< width * height).map { _ in colors[random.next(colors.count)] }
        var second = first
        for row in 20 ..< 30 {
            for column in 40 ..< 70 {
                second[row * width + column] = colors[random.next(colors.count)]
            }
        }
        let decoded = decodeGIF(makeGIF([first, second, second], width: width, height: height))
        // 第三帧和第二帧完全一样，不写
        #expect(decoded.count == 2)
        #expect(decoded.first == first)
        #expect(decoded.last == second)
    }

    @Test(arguments: [2, 4, 16, 256])
    func `LZW 在各种码长和码表清空后都能被系统正确解码`(colorCount: Int) {
        // 300×200 的随机像素产生的码远超 4096 个，会多次清空码表
        let width = 300, height = 200
        var random = Random(state: UInt64(colorCount))
        let colors = (0 ..< colorCount).map { 0xFF00_0000 | UInt32($0 * 65537 + 3) }
        let pixels = (0 ..< width * height).map { _ in colors[random.next(colorCount)] }
        #expect(decodeGIF(makeGIF([pixels], width: width, height: height)).first == pixels)
    }

    @Test func `长串相同像素（码长频繁增长）也能正确解码`() {
        let width = 640, height = 3
        let pixels = (0 ..< width * height).map { $0 < 1000 ? 0xFF11_2233 : 0xFF44_5566 } as [UInt32]
        #expect(decodeGIF(makeGIF([pixels], width: width, height: height)).first == pixels)
    }

    @Test func `超过 256 种颜色时中位切分，误差在每通道 5 位精度以内`() {
        let width = 128, height = 128
        let pixels = (0 ..< width * height).map { index in
            0xFF00_0000 | UInt32(index % 128 * 2) << 16 | UInt32(index / 128 * 2) << 8 | UInt32((index * 7) % 256)
        }
        guard let decoded = decodeGIF(makeGIF([pixels], width: width, height: height)).first else {
            Issue.record("解码失败")
            return
        }
        let worst = zip(pixels, decoded).map { original, result in
            (0 ..< 3).map { channel in
                abs(Int(original >> (channel * 8) & 0xFF) - Int(result >> (channel * 8) & 0xFF))
            }.max() ?? 0
        }.max() ?? 0
        #expect(worst <= 48)
    }

    @Test func `变化矩形`() {
        let width = 10, height = 8
        let old = [UInt32](repeating: 0xFF00_0000, count: width * height)
        var new = old
        #expect(GIFFrameEncoder.changedRect(old, new, width: width, height: height) == nil)
        new[2 * width + 3] = 1
        new[5 * width + 7] = 1
        #expect(
            GIFFrameEncoder.changedRect(old, new, width: width, height: height)
                == .init(x: 3, y: 2, width: 5, height: 4),
        )
    }

    @Test func `帧时长按绝对时间取整，至少 2`() {
        #expect(GIFFormat.delay(from: 0, to: 1.0 / 15) == 7)
        #expect(GIFFormat.delay(from: 1.0 / 15, to: 2.0 / 15) == 6)
        #expect(GIFFormat.delay(from: 0.5, to: 0.505) == 2)
        #expect(GIFFormat.paletteBits(2) == 1)
        #expect(GIFFormat.paletteBits(3) == 2)
        #expect(GIFFormat.paletteBits(256) == 8)
    }
}

struct AudioMixerTests {
    @Test func `两路对齐后相加并限制在 -1～1`() {
        var mixer = AudioMixer(sources: [0, 1], latency: 100, tolerance: 1)
        mixer.push(source: 0, at: 0, samples: [[0.5, 0.5, 0.5, 0.5], [0, 0, 0, 0]])
        // 只有一路有数据、还没超过等待时间：先不输出
        #expect(mixer.pull() == nil)
        mixer.push(source: 1, at: 2, samples: [[0.8, 0.8], [0.1, 0.1]])
        #expect(mixer.pull() == [[0.5, 0.5, 1, 1], [0, 0, 0.1, 0.1]])
    }

    @Test func `一路一直没数据时最多等 latency`() {
        var mixer = AudioMixer(sources: [0, 1], latency: 3, tolerance: 0)
        mixer.push(source: 0, at: 0, samples: [Array(repeating: 0.25, count: 5)])
        mixer.push(source: 1, at: 0, samples: [[0.25]])
        #expect(mixer.pull()?.first == [0.5, 0.25])
        #expect(mixer.pull(flush: true)?.first == [0.25, 0.25, 0.25])
    }

    @Test func `小缝隙当作连续，大缝隙补静音，开始前的采样丢掉`() {
        var mixer = AudioMixer(sources: [0], latency: 0, tolerance: 2)
        mixer.push(source: 0, at: -2, samples: [[9, 9, 0.1, 0.2]])
        mixer.push(source: 0, at: 3, samples: [[0.3]])
        mixer.push(source: 0, at: 8, samples: [[0.4]])
        #expect(mixer.pull(flush: true)?.first == [0.1, 0.2, 0.3, 0, 0, 0, 0, 0, 0.4])
        #expect(mixer.emitted == 9)
    }
}

struct RecordingGeometryTests {
    @Test func `MP4 按 Retina 像素，超过 H.264 上限等比缩小，宽高为偶数`() {
        var options = RecordingOptions()
        #expect(
            RecordingGeometry.outputSize(points: CGSize(width: 801, height: 451), scale: 2, options: options)
                == .init(width: 1602, height: 902),
        )
        let full = RecordingGeometry.outputSize(points: CGSize(width: 2560, height: 1440), scale: 2, options: options)
        #expect(full.width <= 4096 && full.width * full.height <= 4096 * 2304)
        #expect(full.width % 2 == 0 && full.height % 2 == 0)
        options.codec = .hevc
        #expect(
            RecordingGeometry.outputSize(points: CGSize(width: 2560, height: 1440), scale: 2, options: options)
                == .init(width: 5120, height: 2880),
        )
    }

    @Test func `GIF 默认按 pt，高清模式按 Retina`() {
        var options = RecordingOptions(format: .gif)
        let points = CGSize(width: 333, height: 201)
        #expect(RecordingGeometry.outputSize(points: points, scale: 2, options: options) == .init(width: 333, height: 201))
        options.gifHighResolution = true
        #expect(RecordingGeometry.outputSize(points: points, scale: 2, options: options) == .init(width: 666, height: 402))
    }

    @Test func `只有 MP4 录声音；文件名按格式取扩展名`() {
        #expect(!RecordingOptions(format: .gif, systemAudio: true).recordsAudio)
        #expect(RecordingOptions(format: .mp4, microphone: true).recordsAudio)
        let date = Date(timeIntervalSince1970: 0)
        let name = RecordingFileName.make(date: date, format: .gif) { _ in false }
        #expect(name.hasSuffix(".gif") && name.hasPrefix("MAIO "))
    }
}
