import AppKit
import MAIOKit
import MAIOUI
import SwiftUI

/// 弹出面板的显示、定位与粘贴流程。
/// 1. 弹出前记下当前 App 和光标位置（激活 MAIO 之后就拿不到了）；
/// 2. 激活 MAIO，让搜索框可以输入（中文输入法也能用）；
/// 3. 选中后关闭面板 → 写剪贴板 → 切回原 App → 模拟 ⌘V。
@MainActor
final class ClipboardPanelController {
    let model: ClipboardViewModel
    let store: ClipStore
    let paster: Paster
    let monitor: PasteboardMonitor
    private let settings: () -> ClipboardSettings
    let logger: (String) -> Void
    /// 调用其他功能的契约（贴图、翻译）
    let commands: any CommandRegistrar
    private var panel: FloatingPanel<ClipboardPanelView>?
    private var delegate: PanelDelegate?
    private var isOpening = false
    private var previousApp: NSRunningApplication?
    private var keyMonitor: Any?

    struct Dependencies {
        let store: ClipStore
        let paster: Paster
        let monitor: PasteboardMonitor
        let settings: () -> ClipboardSettings
        let logger: (String) -> Void
        let commands: any CommandRegistrar
    }

    init(model: ClipboardViewModel, dependencies: Dependencies) {
        self.model = model
        store = dependencies.store
        paster = dependencies.paster
        monitor = dependencies.monitor
        settings = dependencies.settings
        logger = dependencies.logger
        commands = dependencies.commands
        model.onAction = { [weak self] item, action in self?.handle(action, for: item) }
        model.onClose = { [weak self] in self?.close(restoreFocus: true) }
        model.onPaste = { [weak self] item, plain in self?.paste(item, plainText: plain) }
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func toggle() async {
        if isVisible {
            close(restoreFocus: true)
        } else {
            await show()
        }
    }

    func show() async {
        // 找光标位置可能要等一下（Electron App 第一次要先打开辅助功能），期间再按快捷键不重复打开
        guard !isOpening else { return }
        isOpening = true
        defer { isOpening = false }
        if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current {
            previousApp = front
        }
        let origin = await topLeft(for: settings().popupPosition)
        model.prepareForOpen(searchMode: settings().searchMode)
        let panel = panel ?? makePanel()
        panel.setContentSize(ClipboardPanelView.size)
        panel.setFrameTopLeftPoint(origin)
        AppActivation.activateForcibly()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    /// 在 App 收到按键的入口处先看一遍（早于搜索框和输入法）：
    /// - ⌘⌫ 在文本框里是系统的"删除到行首"，会在 SwiftUI 的 onKeyPress 之前被输入框处理掉（用户实测无效）；
    /// - 不在搜索时，所有按键都在这里处理（`handleBrowsingKey`），不进搜索框；
    /// - 搜索时，输入法正在组字的 ⏎ 做个记号，搜索框据此不把它当成"确认"。
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

    func close(restoreFocus: Bool) {
        removeKeyMonitor()
        guard let panel, panel.isVisible else { return }
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

    private func paste(_ item: ClipItem, plainText: Bool) {
        let target = previousApp
        let current = settings()
        close(restoreFocus: false)
        Task {
            do {
                var payload = try await store.payload(item.id)
                if plainText, let plain = payload.plainTextOnly {
                    payload = plain
                }
                paster.write(payload)
                monitor.skipCurrent()
                if current.moveToTopOnPaste {
                    try await store.touch(item.id)
                }
                if current.pasteDirectly {
                    await paster.paste(into: target)
                } else {
                    target?.activate()
                }
            } catch {
                logger("粘贴失败：\(error.localizedDescription)")
                target?.activate()
            }
        }
    }

    private func makePanel() -> FloatingPanel<ClipboardPanelView> {
        let panel = FloatingPanel(
            rootView: ClipboardPanelView(model: model), size: ClipboardPanelView.size, acceptsKeyboard: true,
        )
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let delegate = PanelDelegate { [weak self] in self?.close(restoreFocus: false) }
        panel.delegate = delegate
        self.delegate = delegate
        self.panel = panel
        return panel
    }

    /// 面板左上角应该放的位置
    private func topLeft(for position: ClipboardSettings.PopupPosition) async -> CGPoint {
        let mouse = NSEvent.mouseLocation
        let pointer = CGRect(origin: mouse, size: .zero)
        switch position {
        case .caret:
            if let caret = await TextCaretLocator.caretRect() {
                return Self.place(around: caret)
            }
            switch settings().caretFallback {
            case .center: return Self.centered(near: mouse)
            case .mouse: return Self.place(around: pointer)
            }
        case .mouse:
            return Self.place(around: pointer)
        case .center:
            return Self.centered(near: mouse)
        }
    }

    private static func place(around anchor: CGRect) -> CGPoint {
        let visible = screen(containing: CGPoint(x: anchor.midX, y: anchor.midY))?.visibleFrame ?? .zero
        return PopupPlacement.topLeft(around: anchor, size: ClipboardPanelView.size, in: visible)
    }

    /// 鼠标所在屏幕的正中间
    private static func centered(near mouse: CGPoint) -> CGPoint {
        let visible = screen(containing: mouse)?.visibleFrame ?? .zero
        return PopupPlacement.centered(size: ClipboardPanelView.size, in: visible)
    }

    private static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(point) } ?? NSScreen.main
    }
}

/// 面板失去焦点（点了别处）时关闭。
@MainActor
private final class PanelDelegate: NSObject, NSWindowDelegate {
    private let resignedKey: () -> Void

    init(resignedKey: @escaping () -> Void) {
        self.resignedKey = resignedKey
    }

    func windowDidResignKey(_: Notification) {
        resignedKey()
    }
}
