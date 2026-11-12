import Foundation
import ImageIO

/// 图片里的文字（用于搜索）：保存在 clip.ocr_text。
/// NULL = 还没识别；空字符串 = 识别过但没有文字（或者图没了、识别失败），不再重试。
/// 识别本身在 `ImageTextIndexer` 里一条一条做，这里只负责挑条目、取图、写结果。
extension ClipStore {
    /// 识别用的图最大边长：太大的图缩一下（5K 截图仍然清楚），避免占太多内存
    static let recognitionPixelSize = 4096

    /// 下一条要识别的：图片条目，或者复制的图片文件（有缩略图的文件条目）；最近用过的先识别
    func nextImageWithoutText() throws -> Int64? {
        var id: Int64?
        try database.query(
            """
            SELECT id FROM clip
            WHERE ocr_text IS NULL AND (kind = 'image' OR (kind = 'files' AND thumbnail IS NOT NULL))
            ORDER BY last_used_at DESC LIMIT 1
            """,
        ) { id = $0.int(0) }
        return id
    }

    /// 识别用的图：图片条目用剪贴板里的数据，图片文件读原文件（不在了返回 nil）
    func imageForRecognition(_ id: Int64) async -> CGImage? {
        guard let payload = try? payload(id) else { return nil }
        let maxSize = Self.recognitionPixelSize
        if let data = payload.data(PasteType.png) ?? payload.data(PasteType.tiff) {
            return await Task.detached(priority: .utility) {
                CGImageSourceCreateWithData(data as CFData, nil).flatMap { Thumbnails.image(from: $0, maxPixelSize: maxSize) }
            }.value
        }
        guard let url = imageFileURL(in: payload) else { return nil }
        return await Task.detached(priority: .utility) { Thumbnails.cgImage(fileURL: url, maxPixelSize: maxSize) }.value
    }

    func setImageText(_ text: String, for id: Int64) throws {
        try database.query("UPDATE clip SET ocr_text = ? WHERE id = ?", [.text(text.lowercased()), .int(id)])
    }
}
