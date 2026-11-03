/// 系统中一个窗口（或没有窗口的 App）的原始信息，由 Infrastructure/WindowCatalog 采集。
struct WindowRecord: Equatable, Sendable {
    let pid: Int32
    let appName: String
    let bundleID: String?
    /// nil 表示 App 没有可切换的窗口
    let windowID: UInt32?
    let title: String
    let isMinimized: Bool
    let isAppHidden: Bool
    /// 在屏幕上的叠放位置（0 = 最前）；不在屏幕上（最小化、隐藏）为 nil
    let zIndex: Int?
}

/// 把采集到的窗口排成切换顺序（纯逻辑，可单测）。
///
/// 顺序：当前屏幕上的窗口按叠放顺序（最前的就是最近使用的）→ 其余窗口按 App 最近使用顺序。
/// alt-tab-macos 维护了完整的焦点历史；这里先用叠放顺序近似，覆盖绝大多数场景。
enum WindowOrdering {
    static func items(
        from records: [WindowRecord],
        appRecency: [String],
        settings: SwitcherSettings,
    ) -> [SwitcherItem] {
        let excluded = Set(settings.excludedBundleIDs)
        let rank = Dictionary(appRecency.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let visible = records.filter { record in
            if let bundleID = record.bundleID, excluded.contains(bundleID) {
                return false
            }
            if record.windowID == nil {
                return settings.showAppsWithoutWindows
            }
            if record.isAppHidden {
                return settings.showHiddenApps
            }
            if record.isMinimized {
                return settings.showMinimizedWindows
            }
            return true
        }
        let sorted = visible.enumerated().sorted { lhs, rhs in
            precedes(lhs.element, rhs.element, rank: rank, tieBreak: lhs.offset < rhs.offset)
        }.map(\.element)
        var seenApps: Set<Int32> = []
        return sorted.compactMap { record in
            if settings.oneItemPerApp {
                guard seenApps.insert(record.pid).inserted else { return nil }
            }
            return SwitcherItem(
                id: .init(pid: record.pid, windowID: record.windowID),
                appName: record.appName,
                bundleID: record.bundleID,
                title: settings.oneItemPerApp ? record.appName : record.title,
                isMinimized: record.isMinimized,
                isHidden: record.isAppHidden,
            )
        }
    }

    private static func precedes(_ lhs: WindowRecord, _ rhs: WindowRecord, rank: [String: Int], tieBreak: Bool) -> Bool {
        switch (lhs.zIndex, rhs.zIndex) {
        case let (left?, right?): return left < right
        case (.some, nil): return true
        case (nil, .some): return false
        case (nil, nil):
            let left = lhs.bundleID.flatMap { rank[$0] } ?? Int.max
            let right = rhs.bundleID.flatMap { rank[$0] } ?? Int.max
            return left != right ? left < right : tieBreak
        }
    }
}
