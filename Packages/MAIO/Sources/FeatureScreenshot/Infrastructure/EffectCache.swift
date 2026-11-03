import CoreGraphics
import CoreImage

/// 马赛克、模糊的计算结果缓存：拖动其他对象时不必重新计算。
final class EffectCache {
    struct Result {
        let image: CGImage
        /// 结果对应的全局矩形（已裁到显示器范围内）
        let rect: CGRect
    }

    private struct Key: Hashable {
        let kind: Int
        let x, y, width, height, parameter: Double
    }

    static let limit = 48

    private var results: [Key: Result] = [:]
    private lazy var ciContext = CIContext(options: [.cacheIntermediates: false])

    /// 马赛克：每块取平均色（缩小再用最近邻放大），不保留原始像素，不可还原
    func mosaic(_ rect: CGRect, block: CGFloat, source: EffectSource) -> Result? {
        cached(kind: 0, rect: rect, parameter: block) {
            let pixels = source.pixelRect(for: rect)
            guard !pixels.isNull, let crop = source.image.cropping(to: pixels) else { return nil }
            let blockPixels = max(2, block * source.scale)
            let width = max(1, Int((pixels.width / blockPixels).rounded(.up)))
            let height = max(1, Int((pixels.height / blockPixels).rounded(.up)))
            guard let space = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ) else { return nil }
            context.interpolationQuality = .high
            context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            return context.makeImage().map { Result(image: $0, rect: source.globalRect(forPixels: pixels)) }
        }
    }

    func blur(_ rect: CGRect, radius: CGFloat, source: EffectSource) -> Result? {
        cached(kind: 1, rect: rect, parameter: radius) {
            let pixels = source.pixelRect(for: rect)
            guard !pixels.isNull, let crop = source.image.cropping(to: pixels) else { return nil }
            let input = CIImage(cgImage: crop)
            let output = input.clampedToExtent().applyingGaussianBlur(sigma: Double(radius * source.scale))
                .cropped(to: input.extent)
            return ciContext.createCGImage(output, from: input.extent)
                .map { Result(image: $0, rect: source.globalRect(forPixels: pixels)) }
        }
    }

    private func cached(kind: Int, rect: CGRect, parameter: CGFloat, make: () -> Result?) -> Result? {
        let key = Key(
            kind: kind, x: rect.minX, y: rect.minY, width: rect.width, height: rect.height, parameter: parameter,
        )
        if let hit = results[key] {
            return hit
        }
        guard let result = make() else { return nil }
        if results.count >= Self.limit {
            results.removeAll()
        }
        results[key] = result
        return result
    }
}
