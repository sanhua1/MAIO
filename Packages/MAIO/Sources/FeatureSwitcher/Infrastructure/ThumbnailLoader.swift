import AppKit
import ScreenCaptureKit

/// 用 ScreenCaptureKit 截取窗口缩略图（需要"屏幕与系统录音"权限）。
/// alt-tab-macos 在 macOS 26 上同样使用 ScreenCaptureKit（references/alt-tab-macos/src/events/WindowCaptureEvents.swift）。
enum ThumbnailLoader {
    /// 缩略图最长边（像素）
    static let maxPixelSize: CGFloat = 480

    /// 逐个返回截好的缩略图；失败的窗口直接跳过（界面上显示 App 图标）。
    static func load(windowIDs: [UInt32]) -> AsyncStream<(UInt32, CGImage)> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                else {
                    continuation.finish()
                    return
                }
                let wanted = Set(windowIDs)
                let windows = content.windows.filter { wanted.contains($0.windowID) }
                await withTaskGroup(of: Void.self) { group in
                    for window in windows.map(WindowBox.init) {
                        group.addTask {
                            if let image = await capture(window.window) {
                                continuation.yield((window.window.windowID, image))
                            }
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func capture(_ window: SCWindow) async -> CGImage? {
        let frame = window.frame
        guard frame.width > 0, frame.height > 0 else { return nil }
        let scale = min(1, maxPixelSize / max(frame.width, frame.height)) * 2
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(frame.width * scale))
        configuration.height = max(1, Int(frame.height * scale))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let filter = SCContentFilter(desktopIndependentWindow: window)
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}

/// SCWindow 是 ScreenCaptureKit 返回的只读快照，没有标记 Sendable；在截图任务之间传递是安全的。
private struct WindowBox: @unchecked Sendable {
    let window: SCWindow
}
