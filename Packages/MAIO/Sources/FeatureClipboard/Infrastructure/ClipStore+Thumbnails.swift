import AppKit
import Foundation

/// 缩略图与预览图。
/// 图片条目直接用剪贴板里的图片数据；复制图片"文件"时剪贴板上只有路径，需要读原文件生成。
/// 解码大图要几十到一百多毫秒，都放到后台任务里做，不占着 ClipStore 这个 actor。
extension ClipStore {
    /// 保存时生成缩略图（列表里显示）。不是图片就返回 nil。
    func makeThumbnail(for payload: ClipPayload) async -> Data? {
        if let url = imageFileURL(in: payload) {
            return await Self.offActor { Thumbnails.make(fileURL: url) }
        }
        guard payload.kind == .image else { return nil }
        return await Self.offActor { Thumbnails.make(payload) }
    }

    /// 文件条目里第一个还在的图片文件
    func imageFileURL(in payload: ClipPayload) -> URL? {
        payload.fileURLs.first {
            Thumbnails.isImageFile($0) && FileManager.default.fileExists(atPath: $0.path)
        }
    }

    /// 给以前保存的文件条目补缩略图（原文件还在才补）。升级软件后调用一次，旧记录也能看到预览。
    @discardableResult
    func backfillFileThumbnails() async throws -> Int {
        var candidates: [(id: Int64, url: URL)] = []
        var seen: Set<Int64> = []
        try database.query(
            """
            SELECT clip.id, clip_data.data FROM clip
            JOIN clip_data ON clip_data.clip_id = clip.id AND clip_data.type = ?
            WHERE clip.kind = 'files' AND clip.thumbnail IS NULL
            """,
            [.text(PasteType.fileURL)],
        ) { row in
            guard let text = row.text(1), let url = URL(string: text), seen.insert(row.int(0)).inserted else { return }
            candidates.append((row.int(0), url))
        }
        var updated = 0
        for (id, url) in candidates where Thumbnails.isImageFile(url) {
            guard let data = await Self.offActor({ Thumbnails.make(fileURL: url) }) else { continue }
            try database.query("UPDATE clip SET thumbnail = ? WHERE id = ?", [.blob(data), .int(id)])
            updated += 1
        }
        return updated
    }

    /// 空格预览用的大图：图片条目用剪贴板里的原始数据；图片文件从磁盘解码，
    /// 原文件不在了回退到归档的缩略图。返回图片和原图的像素尺寸。
    func previewImage(for item: ClipItem, payload: ClipPayload) async -> (image: NSImage, pixelSize: CGSize)? {
        if let data = payload.data(PasteType.png) ?? payload.data(PasteType.tiff) {
            return await Self.offActor { Self.image(from: data) }
        }
        guard item.kind == .files else { return nil }
        if let url = imageFileURL(in: payload) {
            let decoded = await Self.offActor { () -> (NSImage, CGSize)? in
                guard let cgImage = Thumbnails.cgImage(fileURL: url, maxPixelSize: Thumbnails.previewPixelSize)
                else { return nil }
                let size = CGSize(width: cgImage.width, height: cgImage.height)
                return (NSImage(cgImage: cgImage, size: size), size)
            }
            if let decoded {
                return decoded
            }
        }
        let archived = try? thumbnail(item.id)
        return await Self.offActor { archived.flatMap(Self.image(from:)) }
    }

    /// 在后台任务里做同步的图片解码（ImageIO 是线程安全的）
    private static func offActor<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await Task.detached(priority: .utility, operation: work).value
    }

    private static func image(from data: Data) -> (NSImage, CGSize)? {
        guard let image = NSImage(data: data) else { return nil }
        return (image, Thumbnails.pixelSize(data) ?? image.size)
    }
}
