import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 图片条目的缩略图（保存时生成一次，列表直接显示）。ImageIO 是线程安全的，可以在 actor 里调用。
enum Thumbnails {
    /// 列表里显示的缩略图大小
    static let listPixelSize = 240
    /// 空格预览用的大图大小
    static let previewPixelSize = 2048

    static func make(_ payload: ClipPayload) -> Data? {
        guard let data = payload.data(PasteType.png) ?? payload.data(PasteType.tiff),
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        return encode(source: source, maxPixelSize: listPixelSize)
    }

    /// 从文件生成缩略图。复制图片文件（Finder、输入法等）时剪贴板上只有路径，没有图片数据。
    static func make(fileURL: URL, maxPixelSize: Int = listPixelSize) -> Data? {
        cgImage(fileURL: fileURL, maxPixelSize: maxPixelSize).flatMap(png)
    }

    /// 从文件解码出一张缩小到 maxPixelSize 的图（预览大图用，不再编码成 PNG）
    static func cgImage(fileURL: URL, maxPixelSize: Int = listPixelSize) -> CGImage? {
        // 不整个读进内存，ImageIO 按需解码
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions) else { return nil }
        return thumbnail(from: source, maxPixelSize: maxPixelSize)
    }

    /// 扩展名看起来是图片（不读文件内容）。「.uuremote_xxx」这类没有扩展名的文件不会被当成图片。
    static func isImageFile(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    private static func encode(source: CGImageSource, maxPixelSize: Int) -> Data? {
        thumbnail(from: source, maxPixelSize: maxPixelSize).flatMap(png)
    }

    /// 从已经打开的图片数据解码，缩小到 maxPixelSize（识别文字用）
    static func image(from source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        thumbnail(from: source, maxPixelSize: maxPixelSize)
    }

    private static func thumbnail(from source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func png(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    /// 图片的像素尺寸（预览时显示）
    static func pixelSize(_ data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: width, height: height)
    }
}
