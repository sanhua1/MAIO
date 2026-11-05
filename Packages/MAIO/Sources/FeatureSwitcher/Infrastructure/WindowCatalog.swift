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
        let screen = onScreenWindows()
        let zOrder = Dictionary(screen.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        var records: [WindowRecord] = []
        var elements: [UInt32: AXElementBox] = [:]
        for app in apps {
            // App 暂时不响应辅助功能查询（刚启动、正忙）时，用屏幕上的窗口顶替，不让它整个从列表里消失
            let windows = windows(of: app.pid) ?? fallbackWindows(of: app.pid, from: screen)
            if windows.isEmpty {
                records.append(WindowRecord(
                    pid: app.pid, appName: app.name, bundleID: app.bundleID, windowID: nil, title: "",
                    isMinimized: false, isAppHidden: app.isHidden, zIndex: nil,
                ))
            }
            for window in windows {
                let (id, title, minimized) = (window.id, window.title, window.isMinimized)
                if let element = window.element {
                    elements[id] = AXElementBox(element: element)
                }
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
        /// 用屏幕窗口列表顶替时为 nil，切换时再按窗口 ID 查（`element(pid:windowID:)`）
        let element: AXUIElement?
        let title: String
        let isMinimized: Bool
    }

    /// nil 表示查询失败（超时、App 不响应），和"没有窗口"（空数组）不同
    private static func windows(of pid: Int32) -> [AXWindow]? {
        guard let list = axWindows(of: pid) else { return nil }
        return list.compactMap { window in
            guard AXHelper.attribute(window, kAXRoleAttribute, as: String.self) == kAXWindowRole,
                  let id = AXHelper.windowID(of: window) else { return nil }
            let subrole = AXHelper.attribute(window, kAXSubroleAttribute, as: String.self)
            let title = AXHelper.attribute(window, kAXTitleAttribute, as: String.self) ?? ""
            let isStandard = subrole == kAXStandardWindowSubrole || (subrole == kAXDialogSubrole && !title.isEmpty)
            guard isStandard, let size = AXHelper.size(of: window), isLargeEnough(size) else { return nil }
            let minimized = AXHelper.attribute(window, kAXMinimizedAttribute, as: Bool.self) ?? false
            return AXWindow(id: id, element: window, title: title, isMinimized: minimized)
        }
    }

    private static func axWindows(of pid: Int32) -> [AXUIElement]? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, AXHelper.messagingTimeout)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        switch error {
        case .success: return value as? [AXUIElement] ?? []
        // 没有窗口的 App 有时返回这两个错误，不算"不响应"
        case .noValue, .attributeUnsupported: return []
        default: return nil
        }
    }

    /// 查询失败时的替补：这个 App 在屏幕上的普通窗口。拿不到最小化的窗口和标题以外的信息，但至少能切过去。
    private static func fallbackWindows(of pid: Int32, from screen: [ScreenWindow]) -> [AXWindow] {
        screen.filter { $0.pid == pid && isLargeEnough($0.size) }
            .map { AXWindow(id: $0.id, element: nil, title: $0.title, isMinimized: false) }
    }

    private static func isLargeEnough(_ size: CGSize) -> Bool {
        size.width >= 100 && size.height >= 50
    }

    /// 切换时补查替补窗口的辅助功能元素（这时 App 通常已经恢复响应）
    static func element(pid: Int32, windowID: UInt32) -> AXUIElement? {
        axWindows(of: pid)?.first { AXHelper.windowID(of: $0) == windowID }
    }

    private struct ScreenWindow {
        let id: UInt32
        let pid: Int32
        let title: String
        let size: CGSize
    }

    /// 屏幕上的普通层级窗口，按叠放顺序（第一个 = 最前）。
    private static func onScreenWindows() -> [ScreenWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let id = info[kCGWindowNumber as String] as? UInt32,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32 else { return nil }
            let bounds = (info[kCGWindowBounds as String] as? NSDictionary)
                .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .zero
            let title = info[kCGWindowName as String] as? String ?? ""
            return ScreenWindow(id: id, pid: pid, title: title, size: bounds.size)
        }
    }
}
