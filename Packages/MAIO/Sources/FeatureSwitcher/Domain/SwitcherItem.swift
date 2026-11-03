/// 切换器中的一项：一个窗口（或没有窗口的 App）。
struct SwitcherItem: Identifiable, Equatable, Sendable {
    struct ID: Hashable, Sendable {
        let pid: Int32
        /// CGWindowID；App 没有可见窗口时为 nil
        let windowID: UInt32?
    }

    let id: ID
    let appName: String
    let bundleID: String?
    let title: String
    let isMinimized: Bool
    let isHidden: Bool

    var pid: Int32 {
        id.pid
    }

    var windowID: UInt32? {
        id.windowID
    }

    /// 界面显示的标题：窗口标题为空时用 App 名
    var displayTitle: String {
        title.isEmpty ? appName : title
    }
}
