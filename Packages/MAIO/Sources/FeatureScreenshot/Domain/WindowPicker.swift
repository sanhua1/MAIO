import CoreGraphics

/// 冻结时读取的一个屏幕窗口（全局坐标，左上角原点）。顺序与 CGWindowList 一致：越靠前越在上层。
struct WindowInfo: Sendable, Equatable {
    var id: UInt32
    var pid: Int32
    var frame: CGRect
    var layer: Int
    var alpha: Double
    var ownerName: String
    var bundleID: String?
}

/// 从冻结的窗口列表里挑出鼠标下的窗口。
enum WindowPicker {
    static let dockBundleID = "com.apple.dock"
    /// 太小的窗口（例如 1×1 的辅助窗口）不参与识别
    static let minimumSize: CGFloat = 8

    /// 过滤掉不应该被选中的窗口，保持原有的上下顺序。
    static func candidates(_ windows: [WindowInfo], excludingPID: Int32, displays: [CGRect]) -> [WindowInfo] {
        windows.filter { window in
            guard window.pid != excludingPID, window.layer >= 0, window.alpha >= 0.05, window.frame.width >= minimumSize,
                  window.frame.height >= minimumSize else { return false }
            // Window Server 自己的窗口：鼠标指针、菜单栏背景等
            if window.bundleID == nil, window.ownerName == "Window Server" {
                return false
            }
            // 程序坞有一个覆盖整个屏幕的透明窗口（ADR-0011 实验），不排除的话处处都会命中它
            if window.bundleID == dockBundleID, displays.contains(where: { window.frame.contains($0) }) {
                return false
            }
            return true
        }
    }

    static func window(at point: CGPoint, in candidates: [WindowInfo]) -> WindowInfo? {
        candidates.first { $0.frame.contains(point) }
    }
}
