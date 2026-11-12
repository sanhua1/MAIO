import AppKit
import MAIOUI
import SwiftUI

/// 翻译窗口的显示、定位与焦点管理。
/// - 打开时强制激活 MAIO（否则输入框拿不到键盘焦点），关闭时把焦点还给原来的 App；
/// - 内容变高时保持左上角不动（窗口默认以左下角为原点，会往上长）；"屏幕正中间"模式下保持中心不动。
@MainActor
final class TranslateWindowController {
    private let model: TranslateViewModel
    private let settings: () -> TranslateSettings
    private let saveSettings: (TranslateSettings) -> Void
    /// 排查"翻译窗口没出来"用（窗口显示 / 失去焦点 / 关闭）
    private let logger: (String) -> Void
    private var panel: FloatingPanel<TranslateView>?
    private var previousApp: NSRunningApplication?
    private var delegate: PanelDelegate?
    private var topLeft: CGPoint?
    /// "屏幕正中间"模式：窗口中心（随结果变高时上下同时扩展；拖动后以新位置为中心）
    private var center: CGPoint?
    /// 窗口刚显示的时刻：刚弹出就失焦（窗口还没抢到 key 的瞬间）不算"点了别处"
    private var shownAt: ContinuousClock.Instant?

    init(
        model: TranslateViewModel,
        settings: @escaping () -> TranslateSettings,
        saveSettings: @escaping (TranslateSettings) -> Void,
        logger: @escaping (String) -> Void = { _ in },
    ) {
        self.model = model
        self.settings = settings
        self.saveSettings = saveSettings
        self.logger = logger
        model.onClose = { [weak self] in self?.close() }
    }

    var isFocused: Bool {
        NSApp.isActive && (panel?.isKeyWindow ?? false)
    }

    func retranslate() {
        model.translate()
    }

    /// 窗口是怎么打开的
    enum Trigger {
        /// 输入框（或从其他功能传来的文字）：位置按 windowPosition
        case input
        /// 翻译选中的文字：位置按 selectionWindowPosition；rect 是选中文字在屏幕上的位置（拿不到时为 nil）
        case selection(CGRect?)
    }

    /// text 为 nil 时只打开窗口（保留上次的内容）；否则填入并立即翻译。
    func show(text: String?, trigger: Trigger = .input) {
        let current = settings()
        if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current {
            previousApp = front
        }
        model.prepare(text: text)
        let isNew = panel == nil
        let panel = panel ?? makePanel(width: current.windowWidth)
        if !panel.isVisible {
            position(panel, placement: Self.placement(for: trigger, settings: current))
        }
        panel.makeKeyAndOrderFront(nil)
        shownAt = ContinuousClock.now
        logger(
            "翻译窗口显示：新建 \(isNew)，字数 \(text?.count ?? -1)，"
                + "MAIO 在前台 \(NSApp.isActive)，是 key 窗口 \(panel.isKeyWindow)",
        )
        if text != nil {
            model.translate()
        }
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        logger("翻译窗口关闭")
        model.cancel()
        model.isPinned = false
        if settings().windowPosition == .remember, let topLeft {
            var updated = settings()
            updated.rememberedOrigin = [topLeft.x, topLeft.y]
            saveSettings(updated)
        }
        if !panel.dismiss(), NSApp.isActive, let previousApp, !previousApp.isTerminated {
            previousApp.activate()
        }
        previousApp = nil
    }

    func tearDown() {
        close()
        panel?.delegate = nil
        delegate = nil
        panel = nil
    }

    private func makePanel(width: Double) -> FloatingPanel<TranslateView> {
        let panel = FloatingPanel(rootView: TranslateView(model: model, width: width), acceptsKeyboard: true)
        panel.level = .floating
        // 只有顶部标题栏能拖动窗口（TranslateView.header），其余地方可以自由选择文字
        panel.isMovableByWindowBackground = false
        // 窗口大小始终等于 SwiftUI 内容大小（结果陆续出现时自动变高，didResize 保持左上角不动）
        panel.hostingView?.sizingOptions = [.intrinsicContentSize, .minSize, .maxSize]
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // ⌘W 和点关闭按钮一样
        panel.onCloseCommand = { [weak self] in self?.close() }
        // 焦点转到另一个 MAIO 面板（例如在翻译里呼出剪贴板）时不算失焦，见 FloatingPanel 的焦点链
        panel.onFocusLost = { [weak self] in self?.didResignKey() }
        let delegate = PanelDelegate(
            moved: { [weak self] in self?.didMove() },
            resized: { [weak self] in self?.didResize() },
        )
        panel.delegate = delegate
        self.delegate = delegate
        self.panel = panel
        return panel
    }

    private func didResignKey() {
        // 刚弹出的一瞬间可能还没成为 key 就先收到失焦通知（例如从截图流程过来），这时不能关，
        // 否则窗口一闪而过，看起来像"点了翻译没反应"
        if let shownAt, ContinuousClock.now - shownAt < .milliseconds(600) {
            logger("翻译窗口刚显示就失去焦点，忽略")
            return
        }
        let closes = settings().closeOnBlur && !model.isPinned
        logger("翻译窗口失去焦点：失焦关闭 \(settings().closeOnBlur)，固定 \(model.isPinned) → \(closes ? "关闭" : "保留")")
        guard closes else { return }
        close()
    }

    private func didMove() {
        guard let panel else { return }
        topLeft = CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
        if center != nil {
            center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        }
    }

    private func didResize() {
        guard let panel else { return }
        if let center {
            let frame = panel.frame
            let visible = panel.screen?.visibleFrame ?? frame
            let origin = CGPoint(
                x: center.x - frame.width / 2,
                y: min(max(center.y - frame.height / 2, visible.minY), visible.maxY - frame.height),
            )
            guard origin != frame.origin else { return }
            panel.setFrameOrigin(origin)
            self.center = center
            return
        }
        guard let topLeft, panel.frame.maxY != topLeft.y || panel.frame.minX != topLeft.x else { return }
        panel.setFrameTopLeftPoint(topLeft)
    }

    /// 窗口放哪
    private enum Placement {
        case center
        case mouse
        case remembered([Double]?)
        /// 选中文字的下方，放不下时放上方
        case below(CGRect)
    }

    private static func placement(for trigger: Trigger, settings: TranslateSettings) -> Placement {
        switch trigger {
        case .input:
            switch settings.windowPosition {
            case .center: .center
            case .followMouse: .mouse
            case .remember: .remembered(settings.rememberedOrigin)
            }
        case let .selection(rect):
            switch settings.selectionWindowPosition {
            case .center: .center
            case .mouse: .mouse
            case .nearSelection: rect.map(Placement.below) ?? .mouse
            }
        }
    }

    private func position(_ panel: NSWindow, placement: Placement) {
        let mouse = NSEvent.mouseLocation
        let anchor: CGPoint = if case let .below(rect) = placement {
            CGPoint(x: rect.midX, y: rect.midY)
        } else {
            mouse
        }
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.contentView?.fittingSize ?? panel.frame.size
        panel.setContentSize(size)
        center = nil
        // 按展开后的高度预留空间
        let reserve = min(visible.height, max(size.height, 420))
        let point: CGPoint
        switch placement {
        case .center:
            let middle = CGPoint(x: visible.midX, y: visible.midY)
            center = middle
            panel.setFrameOrigin(CGPoint(x: middle.x - panel.frame.width / 2, y: middle.y - panel.frame.height / 2))
            topLeft = CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
            return
        case .mouse:
            point = CGPoint(x: mouse.x - 30, y: mouse.y - 12)
        case let .remembered(origin):
            point = origin.flatMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
                ?? CGPoint(x: visible.midX - size.width / 2, y: visible.maxY - visible.height * 0.2)
        case let .below(rect):
            let fitsBelow = rect.minY - 8 - reserve >= visible.minY
            point = CGPoint(x: rect.minX, y: fitsBelow ? rect.minY - 8 : rect.maxY + 8 + reserve)
        }
        // 保证整个窗口在屏幕内
        let clamped = CGPoint(
            x: min(max(point.x, visible.minX + 8), visible.maxX - size.width - 8),
            y: min(max(point.y, visible.minY + reserve), visible.maxY - 8),
        )
        topLeft = clamped
        panel.setFrameTopLeftPoint(clamped)
    }
}

/// 把窗口事件转给控制器（移动、改变大小）。
@MainActor
private final class PanelDelegate: NSObject, NSWindowDelegate {
    private let moved: () -> Void
    private let resized: () -> Void

    init(moved: @escaping () -> Void, resized: @escaping () -> Void) {
        self.moved = moved
        self.resized = resized
    }

    func windowDidMove(_: Notification) {
        moved()
    }

    func windowDidResize(_: Notification) {
        resized()
    }
}
