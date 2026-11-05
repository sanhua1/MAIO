import AppKit
import ApplicationServices
import os

/// 对窗口 / App 执行操作：切换、关闭、最小化、隐藏、退出。
///
/// 切换流程：取消隐藏 / 最小化 → SkyLight 把具体窗口设为前台 + 键盘焦点（不可用时退回公开 API）→ AX 提升
/// → 约 150ms 后检查目标是否在最上层，不在就重试（最多 2 次）。每次结果都写日志（类别 switcher）。
@MainActor
enum WindowActions {
    static let verifyDelay: Duration = .milliseconds(150)
    static let maxRetries = 2

    static func focus(_ item: SwitcherItem, element: AXUIElement?, logger: Logger) {
        guard let app = NSRunningApplication(processIdentifier: item.pid) else { return }
        if app.isHidden {
            app.unhide()
        }
        guard let windowID = item.windowID else {
            // 没有窗口的 App：激活即可（会打开它的默认窗口）
            app.activate(options: [.activateAllWindows])
            logger.notice("切换：\(item.appName, privacy: .public)（无窗口，激活 App）")
            return
        }
        guard let element = element ?? WindowCatalog.element(pid: item.pid, windowID: windowID) else {
            // App 仍不响应辅助功能查询：只能按窗口 ID 用 SkyLight 切过去
            if !SkyLightFocus.focus(pid: app.processIdentifier, windowID: windowID) {
                app.activate(options: [])
            }
            logger.notice("切换：\(item.appName, privacy: .public) #\(windowID)（无辅助功能元素）")
            return
        }
        if item.isMinimized {
            AXHelper.set(element, kAXMinimizedAttribute, kCFBooleanFalse)
        }
        bringToFront(app: app, element: element, windowID: windowID)
        Task { await verify(item, app: app, element: element, windowID: windowID, logger: logger) }
    }

    private static func bringToFront(app: NSRunningApplication, element: AXUIElement, windowID: CGWindowID) {
        if !SkyLightFocus.focus(pid: app.processIdentifier, windowID: windowID) {
            app.activate(options: [])
        }
        raise(element)
    }

    private static func verify(
        _ item: SwitcherItem, app: NSRunningApplication, element: AXUIElement, windowID: CGWindowID, logger: Logger,
    ) async {
        let method = SkyLightFocus.isAvailable ? "SkyLight" : "公开 API"
        for attempt in 0 ... maxRetries {
            try? await Task.sleep(for: verifyDelay)
            let top = ScreenOrder.topWindowID()
            if top == windowID {
                logger.notice("切换：\(item.appName, privacy: .public) #\(windowID)（\(method, privacy: .public)）成功，重试 \(attempt) 次")
                return
            }
            let blocker = top.map { "\(ScreenOrder.ownerName(of: $0))#\($0)" } ?? "无"
            guard attempt < maxRetries else {
                logger.error("切换：\(item.appName, privacy: .public) #\(windowID) 失败，最上层仍是 \(blocker, privacy: .public)")
                return
            }
            logger.warning("切换：\(item.appName, privacy: .public) #\(windowID) 被 \(blocker, privacy: .public) 盖住，重试")
            bringToFront(app: app, element: element, windowID: windowID)
        }
    }

    static func close(element: AXUIElement?) {
        guard let element, let button: AXUIElement = AXHelper.attribute(element, kAXCloseButtonAttribute) else { return }
        AXHelper.perform(button, kAXPressAction)
    }

    static func minimize(element: AXUIElement?) {
        guard let element else { return }
        AXHelper.set(element, kAXMinimizedAttribute, kCFBooleanTrue)
    }

    static func hide(pid: Int32) {
        NSRunningApplication(processIdentifier: pid)?.hide()
    }

    static func quit(pid: Int32) {
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }

    private static func raise(_ element: AXUIElement) {
        AXHelper.set(element, kAXMainAttribute, kCFBooleanTrue)
        AXHelper.perform(element, kAXRaiseAction)
    }
}
