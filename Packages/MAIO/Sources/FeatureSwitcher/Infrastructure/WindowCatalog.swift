import AppKit
import ApplicationServices

/// 采集当前桌面（Space）上可切换的窗口。只用公开 API + `_AXUIElementGetWindow`。
///
/// 规则参考 alt-tab-macos 的 WindowAdmissionResolver（references/alt-tab-macos/src/switcher/state/），独立实现：
/// 只要角色为 AXWindow、子角色为标准窗口（或有标题的对话框）、尺寸不小于 100×50 的窗口。
/// 限制：`kAXWindows` 只返回当前桌面的窗口，其他桌面的窗口不会出现（见 README）。
enum WindowCatalog {
    struct Snapshot: Sendable {
        let records: [WindowRecord]
        let elements: [UInt32: AXElementBox]
    }

    struct AppInfo: Sendable {
        let pid: Int32
        let name: String
        let bundleID: String?
        let isHidden: Bool
    }

    /// 在主线程收集 App 列表（NSWorkspace 需要），然后在后台查询各 App 的窗口。
    @MainActor
    static func snapshot() async -> Snapshot {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ownPID && !$0.isTerminated }
            .map { AppInfo(
                pid: $0.processIdentifier,
                name: $0.localizedName ?? "",
                bundleID: $0.bundleIdentifier,
                isHidden: $0.isHidden,
            ) }
        return await Task.detached(priority: .userInitiated) { collect(apps) }.value
    }

    private static func collect(_ apps: [AppInfo]) -> Snapshot {
        let zOrder = onScreenZOrder()
        var records: [WindowRecord] = []
        var elements: [UInt32: AXElementBox] = [:]
        for app in apps {
            let windows = windows(of: app.pid)
            if windows.isEmpty {
                records.append(WindowRecord(
                    pid: app.pid, appName: app.name, bundleID: app.bundleID, windowID: nil, title: "",
                    isMinimized: false, isAppHidden: app.isHidden, zIndex: nil,
                ))
            }
            for window in windows {
                let (id, title, minimized) = (window.id, window.title, window.isMinimized)
                elements[id] = AXElementBox(element: window.element)
                records.append(WindowRecord(
                    pid: app.pid, appName: app.name, bundleID: app.bundleID, windowID: id, title: title,
                    isMinimized: minimized, isAppHidden: app.isHidden,
                    zIndex: minimized || app.isHidden ? nil : zOrder[id],
                ))
            }
        }
        return Snapshot(records: records, elements: elements)
    }

    private struct AXWindow {
        let id: UInt32
        let element: AXUIElement
        let title: String
        let isMinimized: Bool
    }

    private static func windows(of pid: Int32) -> [AXWindow] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, AXHelper.messagingTimeout)
        guard let list: [AXUIElement] = AXHelper.attribute(app, kAXWindowsAttribute) else { return [] }
        return list.compactMap { window in
            guard AXHelper.attribute(window, kAXRoleAttribute, as: String.self) == kAXWindowRole,
                  let id = AXHelper.windowID(of: window) else { return nil }
            let subrole = AXHelper.attribute(window, kAXSubroleAttribute, as: String.self)
            let title = AXHelper.attribute(window, kAXTitleAttribute, as: String.self) ?? ""
            let isStandard = subrole == kAXStandardWindowSubrole || (subrole == kAXDialogSubrole && !title.isEmpty)
            guard isStandard, let size = AXHelper.size(of: window), size.width >= 100, size.height >= 50 else { return nil }
            let minimized = AXHelper.attribute(window, kAXMinimizedAttribute, as: Bool.self) ?? false
            return AXWindow(id: id, element: window, title: title, isMinimized: minimized)
        }
    }

    /// 屏幕上普通层级窗口的叠放顺序（0 = 最前）。
    private static func onScreenZOrder() -> [UInt32: Int] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var order: [UInt32: Int] = [:]
        for info in list where (info[kCGWindowLayer as String] as? Int) == 0 {
            guard let id = info[kCGWindowNumber as String] as? UInt32, order[id] == nil else { continue }
            order[id] = order.count
        }
        return order
    }
}
