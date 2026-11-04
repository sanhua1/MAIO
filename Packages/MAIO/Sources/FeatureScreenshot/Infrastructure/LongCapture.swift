import CoreGraphics
import Foundation
import ScreenCaptureKit

extension GrayFrame {
    /// 转成灰度（用于计算偏移）
    init?(_ image: CGImage) {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue,
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.init(width: width, height: height, pixels: pixels)
    }
}

/// 收集每一帧要用的那段行，最后一次性合成（spec 4.6 第 5 条）。
/// 每段立即复制成独立的小图，不持有整帧，内存只和最终长图差不多；同时保留一份缩小的，用于右侧的长条预览。
/// 拼接位置由 `StitchPlan` 按绝对坐标决定（ADR-0014 修订三）：往下滚只写下半帧，往回滚不重复写。
struct LongImageBuilder: @unchecked Sendable {
    private struct Part {
        var image: CGImage
        var thumbnail: CGImage
        /// 这段小图对应帧里的起始行
        var origin: Int
    }

    private(set) var plan: StitchPlan
    private var parts: [Int: Part] = [:]
    private var frameCount = 1
    let width: Int
    /// 预览相对原图的缩放
    let previewScale: CGFloat

    /// previewWidth：预览图的宽度（像素）
    init(first: CGImage, previewWidth: Int = 320) {
        plan = StitchPlan(frameHeight: first.height)
        plan.begin(frame: 0)
        width = first.width
        previewScale = min(1, CGFloat(previewWidth) / CGFloat(max(first.width, 1)))
        // 复制一份：视频流的帧来自系统的缓冲池，一直拿着会占用缓冲区
        let image = Self.copy(first, rows: 0 ..< first.height) ?? first
        parts[0] = Part(image: image, thumbnail: Self.scaled(image, by: previewScale) ?? image, origin: 0)
    }

    var height: Int {
        plan.canvasHeight
    }

    /// 接上相对上一帧滚动了 offset 行的一帧（正 = 往下滚）。返回是否有新内容。
    @discardableResult
    mutating func append(_ frame: CGImage, offset: Int) -> Bool {
        guard frame.width == width, frame.height == plan.frameHeight else { return false }
        let index = frameCount
        switch plan.append(frame: index, offset: offset) {
        case .inside:
            return true
        case let .written(rows):
            guard let strip = Self.copy(frame, rows: rows) else { return false }
            parts[index] = Part(image: strip, thumbnail: Self.scaled(strip, by: previewScale) ?? strip, origin: rows.lowerBound)
            frameCount += 1
            // 被覆盖的段不再需要
            let used = plan.usedFrames
            parts = parts.filter { used.contains($0.key) }
            return true
        }
    }

    /// 合成长图
    func compose() -> CGImage? {
        compose(factor: 1, thumbnails: false)
    }

    /// 合成缩小的预览
    func preview() -> CGImage? {
        compose(factor: previewScale, thumbnails: true)
    }

    /// 按计划把各段画到一张图上。factor 是相对原图的缩放
    private func compose(factor: CGFloat, thumbnails: Bool) -> CGImage? {
        let total = CGFloat(plan.canvasHeight) * factor
        let scaledWidth = CGFloat(width) * factor
        guard let context = Self.context(
            width: Int(scaledWidth.rounded()), height: Int(total.rounded()), like: parts.values.first?.image,
        ) else { return nil }
        context.interpolationQuality = .high
        for strip in plan.strips {
            guard let part = parts[strip.frame] else { continue }
            let fullHeight = CGFloat(plan.frameHeight - part.origin) * factor
            let top = CGFloat(strip.top) * factor
            let start = CGFloat(strip.start - part.origin) * factor
            let stripHeight = CGFloat(strip.height) * factor
            // CGContext 原点在左下角：这一段画在从上往下 top 的位置
            context.saveGState()
            context.clip(to: CGRect(x: 0, y: total - top - stripHeight, width: scaledWidth, height: stripHeight))
            context.draw(
                thumbnails ? part.thumbnail : part.image,
                in: CGRect(x: 0, y: total - top + start - fullHeight, width: scaledWidth, height: fullHeight),
            )
            context.restoreGState()
        }
        return context.makeImage()
    }

    /// 复制帧里的若干行成独立的图（cropping 会持有整帧的数据）
    private static func copy(_ image: CGImage, rows: Range<Int>) -> CGImage? {
        guard let cropped = image.cropping(to: CGRect(x: 0, y: rows.lowerBound, width: image.width, height: rows.count)),
              let context = context(width: cropped.width, height: cropped.height, like: image) else { return nil }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
        return context.makeImage()
    }

    private static func scaled(_ image: CGImage, by factor: CGFloat) -> CGImage? {
        let width = max(1, Int((CGFloat(image.width) * factor).rounded()))
        let height = max(1, Int((CGFloat(image.height) * factor).rounded()))
        guard let context = context(width: width, height: height, like: image) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// RGB 上下文：沿用截图的色彩空间（显示器的），不是 RGB 时用 sRGB
    private static func context(width: Int, height: Int, like image: CGImage?) -> CGContext? {
        let space = image?.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard let space, width > 0, height > 0 else { return nil }
        return CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue,
        )
    }
}
