import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 编码 PNG、写剪贴板、保存文件。
enum ImageExporter {
    static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// 缩略图（最长边 maxPixel），用于历史面板。
    static func thumbnailPNG(fromPNG data: Data, maxPixel: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return pngData(thumbnail)
    }

    /// 只写 PNG，不写 TIFF：TIFF 不压缩（5K 全屏约 60 MB），而且会被剪贴板历史原样记录下来。
    @MainActor static func copyToPasteboard(png: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
    }

    @MainActor static func copyToPasteboard(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Pictures/MAIO", directoryHint: .isDirectory)
    }

    /// 写到文件夹里，文件名按时间生成。返回文件位置。
    static func save(png: Data, toDirectory directory: URL, date: Date) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = ScreenshotFileName.make(date: date) { name in
            FileManager.default.fileExists(atPath: directory.appending(path: name).path)
        }
        let url = directory.appending(path: name)
        try png.write(to: url, options: .atomic)
        return url
    }
}
