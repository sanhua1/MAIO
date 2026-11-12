import Foundation

/// 从截图历史拖出去的图片：先复制一份到临时目录，拖的是这份副本。
/// 不能直接拖历史目录里的文件：同一个磁盘上拖进访达默认是"移动"，会把历史里的图拿走；文件名也只是 original.png。
enum HistoryDragCopy {
    /// 拖出去的副本放这里，每次拖一个子目录（文件名可以和截图时间一致，不会撞名）
    static let folder = FileManager.default.temporaryDirectory.appending(path: "MAIO-drag", directoryHint: .isDirectory)
    /// 超过这么久的副本删掉（聊天 App 可能在发送时才读文件，不能拖完马上删）
    static let keepFor: TimeInterval = 600

    static func make(from source: URL, date: Date) -> URL? {
        let fileManager = FileManager.default
        removeStale()
        let target = folder
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .appending(path: ScreenshotFileName.make(date: date) { _ in false })
        do {
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            // APFS 上是克隆，几 MB 的图也是瞬间完成
            try fileManager.copyItem(at: source, to: target)
            return target
        } catch {
            return nil
        }
    }

    private static func removeStale(now: Date = Date()) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles],
        ) else { return }
        for entry in entries {
            let created = (try? entry.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            if now.timeIntervalSince(created) > keepFor {
                try? fileManager.removeItem(at: entry)
            }
        }
    }
}
