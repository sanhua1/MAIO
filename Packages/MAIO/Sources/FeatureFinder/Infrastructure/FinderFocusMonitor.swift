import AppKit
import ApplicationServices

/// 判断 Finder 的焦点是不是在文本框里（重命名、搜索框、前往文件夹），结果交给改键过滤器（ADR-0017）。
/// 主要靠 AXObserver 的焦点变化通知；Finder 在前台期间每 0.5 秒再查一次兜底。
@MainActor
final class FinderFocusMonitor {
    /// 焦点是否在文本框里
    var onEditingChange: (Bool) -> Void = { _ in }
    /// 每次轮询（Finder 在前台时）
    var onTick: () -> Void = {}

    private var observer: AXObserver?
    private var application: AXUIElement?
    private var pid: pid_t = 0
    private var pollTask: Task<Void, Never>?
    private var lastEditing: Bool?

    static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    /// Finder 到前台 / 离开前台
    func setActive(_ active: Bool) {
        guard active else {
            pollTask?.cancel()
            pollTask = nil
            return
        }
        attach()
        refresh()
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                self?.refresh()
                self?.onTick()
            }
        }
    }

    func stop() {
        setActive(false)
        detach()
    }

    /// 重新查一次焦点
    func refresh() {
        let editing = application.map(Self.isEditing) ?? false
        guard editing != lastEditing else { return }
        lastEditing = editing
        onEditingChange(editing)
    }

    static func isEditing(_ application: AXUIElement) -> Bool {
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        // CFGetTypeID 已确认类型，这里的转换一定成功
        let element = unsafeDowncast(focused, to: AXUIElement.self)
        return [kAXRoleAttribute, kAXSubroleAttribute].contains { attribute in
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
            return (value as? String).map(textRoles.contains) ?? false
        }
    }

    /// Finder 重启后 pid 会变，每次到前台都检查一下
    private func attach() {
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: FinderKeymap.bundleID).first
        else {
            detach()
            return
        }
        let newPID = finder.processIdentifier
        guard newPID != pid || observer == nil else { return }
        detach()
        pid = newPID
        let app = AXUIElementCreateApplication(newPID)
        // Finder 卡住时不要拖住主线程
        AXUIElementSetMessagingTimeout(app, 0.2)
        application = app
        var created: AXObserver?
        guard AXObserverCreate(newPID, focusCallback, &created) == .success, let created else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(created, app, kAXFocusedUIElementChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        application = nil
        pid = 0
        lastEditing = nil
    }
}

/// AXObserver 回调在主线程的 run loop 上执行
private let focusCallback: AXObserverCallback = { _, _, _, refcon in
    guard let refcon else { return }
    let monitor = Unmanaged<FinderFocusMonitor>.fromOpaque(refcon).takeUnretainedValue()
    MainActor.assumeIsolated { monitor.refresh() }
}
