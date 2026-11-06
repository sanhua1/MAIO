import AppKit
import MAIOKit
import MAIOUI
import SwiftUI

/// 面板的显示、定位、按键和打开流程（做法同剪贴板面板）：
/// 1. 弹出前记下当前 App；
/// 2. 强制激活 MAIO，让搜索框能输入（中文输入法也能用）；
/// 3. 打开选中项后关闭面板，焦点交给被打开的 App；Esc 关闭时焦点还给原来的 App。
@MainActor
final class LauncherController {
    let model: LauncherViewModel
    private let settings: () -> LauncherSettings
    private let onRecord: (UsageBook) -> Void
    private let logger: (String) -> Void
    private let perform: @MainActor (String) async throws -> Void
    private let showError: (String) -> Void
    private var panel: FloatingPanel<LauncherPanelView>?
    private var delegate: LauncherPanelDelegate?
    private var previousApp: NSRunningApplication?
    private var keyMonitor: Any?
    private var closedAt: Date?

    /// `perform` 执行 MAIO 命令；`showError` 提示命令、系统操作失败
    init(
        model: LauncherViewModel, settings: @escaping () -> LauncherSettings,
        onRecord: @escaping (UsageBook) -> Void, logger: @escaping (String) -> Void,
        perform: @escaping @MainActor (String) async throws -> Void, showError: @escaping (String) -> Void,
    ) {
        self.model = model
        self.settings = settings
        self.onRecord = onRecord
        self.logger = logger
        self.perform = perform
        self.showError = showError
        model.onOpen = { [weak self] item, reveal in self?.open(item, reveal: reveal) }
        model.onClose = { [weak self] in self?.close(restoreFocus: true) }
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func toggle(source: LauncherSource = .all) {
        if isVisible {
            close(restoreFocus: true)
        } else {
            show(source: source)
        }
    }

    func show(source: LauncherSource) {
        if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current {
            previousApp = front
        }
        let current = settings()
        model.settings = current
        let keep = closedAt.map { Date().timeIntervalSince($0) <= current.keepQuerySeconds } ?? false
        model.prepareForOpen(keepQuery: keep && source == .all, running: LauncherActions.runningAppIDs())
        if source != .all {
            model.selectedSource = source
        }
        let panel = panel ?? makePanel()
        panel.setContentSize(LauncherPanelView.size)
        panel.setFrameTopLeftPoint(Self.topLeft())
        AppActivation.activateForcibly()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func close(restoreFocus: Bool) {
        removeKeyMonitor()
        guard let panel, panel.isVisible else { return }
        closedAt = Date()
        panel.orderOut(nil)
        if restoreFocus, NSApp.isActive, let previousApp, !previousApp.isTerminated {
            previousApp.activate()
        }
    }

    func tearDown() {
        removeKeyMonitor()
        panel?.orderOut(nil)
        panel?.delegate = nil
        panel = nil
        delegate = nil
    }

    /// 命令类：先关面板、把焦点还给原来的 App，稍等再执行（"在 Finder 当前位置……""窗口截图"要看最前面的 App）
    private static let commandDelay: Duration = .milliseconds(150)

    private func open(_ item: LauncherItem, reveal: Bool) {
        model.record(item)
        onRecord(model.usage)
        close(restoreFocus: item.isCommand)
        // 应用、文件已经被删掉（索引还没来得及更新）：提示一下，从列表里拿掉，不再假装打开
        if let path = item.path, !FileManager.default.fileExists(atPath: path) {
            model.removeMissingApps()
            previousApp?.activate()
            showError("\(item.title) 已经不在了：\(path)")
            return
        }
        if reveal, item.path != nil {
            LauncherActions.reveal(item)
            return
        }
        let logger = logger
        let showError = showError
        let perform = perform
        let fallback = previousApp
        Task {
            do {
                if item.isCommand {
                    try await Task.sleep(for: Self.commandDelay)
                }
                try await LauncherActions.open(item, perform: perform)
            } catch {
                logger("打开失败：\(item.title)：\(error.localizedDescription)")
                if !item.isCommand {
                    fallback?.activate()
                }
                showError("\(item.title)：\(error.localizedDescription)")
            }
        }
    }

    private func makePanel() -> FloatingPanel<LauncherPanelView> {
        let panel = FloatingPanel(rootView: LauncherPanelView(model: model), size: LauncherPanelView.size, acceptsKeyboard: true)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.onCloseCommand = { [weak self] in self?.close(restoreFocus: true) }
        let delegate = LauncherPanelDelegate { [weak self] in self?.close(restoreFocus: false) }
        panel.delegate = delegate
        self.delegate = delegate
        self.panel = panel
        return panel
    }

    /// 搜索框这一行的中线在屏幕从下往上的这个比例处（黄金分割）
    static let searchLineRatio: CGFloat = 0.618

    /// 鼠标所在屏幕，水平居中；搜索框中线在屏幕高度 61.8% 处（不超出菜单栏和程序坞）
    private static func topLeft() -> CGPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(mouse) } ?? NSScreen.main
        let frame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = screen?.visibleFrame ?? frame
        let size = LauncherPanelView.size
        let top = frame.minY + frame.height * searchLineRatio + LauncherPanelView.searchHeight / 2
        let clamped = min(visible.maxY, max(top, visible.minY + size.height))
        return CGPoint(x: visible.midX - size.width / 2, y: clamped)
    }

    // MARK: 按键

    /// 在按键到达搜索框之前先看一遍（早于输入法）。输入法正在组字时全部放行。
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, self.panel?.isKeyWindow == true else { return false }
                return self.intercept(event)
            }
            return handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    private enum Key {
        static let returnKey: UInt16 = 36
        static let enter: UInt16 = 76
        static let escape: UInt16 = 53
        static let tab: UInt16 = 48
        static let up: UInt16 = 126
        static let down: UInt16 = 125
        static let p: UInt16 = 35
        static let n: UInt16 = 45
        static let c: UInt16 = 8
    }

    /// 返回 true 表示按键已处理
    private func intercept(_ event: NSEvent) -> Bool {
        if (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true {
            return false
        }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch (event.keyCode, modifiers) {
        case (Key.up, []), (Key.p, .control): model.move(by: -1)
        case (Key.down, []), (Key.n, .control): model.move(by: 1)
        case (Key.returnKey, []), (Key.enter, []): model.openSelected(reveal: false)
        case (Key.returnKey, .command), (Key.enter, .command): model.openSelected(reveal: true)
        case (Key.escape, []): model.escape()
        // ← → 留给搜索框移动光标，只用 Tab 切换来源
        case (Key.tab, []): model.cycleSource(forward: true)
        case (Key.tab, .shift): model.cycleSource(forward: false)
        case (KeyCodes.delete, []): return model.deleteOnEmpty()
        default:
            return commandShortcut(event, modifiers: modifiers)
        }
        return true
    }

    /// ⌘C / ⌘⇧C 复制，⌘1～9 快速打开；其他 ⌘ 组合交给系统（⌘A、⌘V 等在搜索框里照常用）
    private func commandShortcut(_ event: NSEvent, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard modifiers.contains(.command), modifiers.isSubset(of: [.command, .shift]) else { return false }
        if event.keyCode == Key.c {
            return copySelected(asFile: modifiers.contains(.shift))
        }
        guard modifiers == .command, let digit = event.charactersIgnoringModifiers?.first?.wholeNumberValue, digit > 0 else {
            return false
        }
        model.openQuick(slot: digit)
        return true
    }
}

private extension LauncherController {
    /// 搜索框里选中了文字时 ⌘C 是普通复制；否则复制所选结果的路径（⌘⇧C 复制文件）
    func copySelected(asFile: Bool) -> Bool {
        let editor = NSApp.keyWindow?.firstResponder as? NSTextView
        if !asFile, let editor, editor.selectedRange().length > 0 {
            return false
        }
        guard let item = model.selected, LauncherActions.copy(item, asFile: asFile) else { return false }
        NSSound(named: "Pop")?.play()
        return true
    }
}

/// 面板失去焦点（点了别处）时关闭
@MainActor
private final class LauncherPanelDelegate: NSObject, NSWindowDelegate {
    private let resignedKey: () -> Void

    init(resignedKey: @escaping () -> Void) {
        self.resignedKey = resignedKey
    }

    func windowDidResignKey(_: Notification) {
        resignedKey()
    }
}
