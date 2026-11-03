import AppKit
import Observation

/// 切换面板的界面状态（主线程）。
@MainActor
@Observable
final class SwitcherViewModel {
    var items: [SwitcherItem] = []
    var selectedIndex = 0
    var thumbnails: [SwitcherItem.ID: NSImage] = [:]
    var icons: [Int32: NSImage] = [:]
    var showThumbnails = true
    /// 网格列数（由控制器根据项数和屏幕宽度计算）
    var columns = 1
    /// 鼠标悬停的项：只做浅色高亮，不改变选中项（松手切换的仍是键盘选中的那个）
    var hoveredID: SwitcherItem.ID?

    /// 点击：选中并确认
    @ObservationIgnored var onClick: ((Int) -> Void)?
}
