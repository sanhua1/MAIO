import AppKit

/// 窗口缩略图缓存：跨切换会话保留，下次打开面板时先显示上次的截图，后台再换成最新的，避免"先闪图标"。
@MainActor
final class ThumbnailCache {
    private var images: [UInt32: NSImage] = [:]
    /// 最多保留的窗口数（每张约 0.5–1MB）
    let capacity = 64

    func image(for windowID: UInt32) -> NSImage? {
        images[windowID]
    }

    func store(_ image: NSImage, for windowID: UInt32) {
        images[windowID] = image
    }

    /// 只保留仍然存在的窗口，并限制数量。
    func retain(only windowIDs: [UInt32]) {
        let keep = Set(windowIDs.prefix(capacity))
        images = images.filter { keep.contains($0.key) }
    }
}
