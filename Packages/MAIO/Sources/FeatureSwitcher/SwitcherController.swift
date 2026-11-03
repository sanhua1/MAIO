import AppKit
import MAIOKit
import MAIOUI

/// 一次窗口切换的完整流程：键盘会话 → 采集窗口 → 延迟显示面板 → 松手切换。
@MainActor
final class SwitcherController {
    private struct Active {
        let keyboard: any KeyboardSession
        let trigger: KeyChord
        let reverse: Bool
        var session: SwitcherSession?
        /// 窗口列表准备好之前到达的按键，准备好后按顺序重放
        var pending: [KeyEvent] = []
        var elements: [UInt32: AXElementBox] = [:]
    }

    /// 兜底：最长会话时间，超时自动取消，保证键盘不会被一直占用
    static let maxSessionDuration: Duration = .seconds(60)
    /// 兜底：定期检查修饰键是否已经松开（"松开"事件丢失时）
    static let releasePollInterval: Duration = .milliseconds(120)

    private let context: any FeatureContext
    private let appRecency: () -> [String]
    private var active: Active?
    private var tasks: [Task<Void, Never>] = []
    private let model = SwitcherViewModel()
    private let thumbnails = ThumbnailCache()
    private var panel: FloatingPanel<SwitcherPanelView>?

    init(context: any FeatureContext, appRecency: @escaping () -> [String]) {
        self.context = context
        self.appRecency = appRecency
        model.onClick = { [weak self] index in
            self?.select(index)
            self?.finish(confirm: true)
        }
    }

    var isActive: Bool {
        active != nil
    }

    /// trigger：触发的组合键（来自快捷键）；从菜单 / URL 调用时为 nil，此时不会因松开修饰键而确认。
    func start(trigger: KeyChord?, reverse: Bool) {
        guard active == nil else { return }
        let keyboard = context.input.beginKeyboardSession()
        let chord = trigger ?? KeyChord(keyCode: KeyCodes.tab, modifiers: [])
        active = Active(keyboard: keyboard, trigger: chord, reverse: reverse)
        tasks.append(Task { [weak self] in
            for await event in keyboard.events {
                self?.handle(event)
            }
        })
        tasks.append(Task { [weak self] in await self?.prepare() })
    }

    func stop() {
        if active != nil {
            finish(confirm: false)
        }
    }

    // MARK: 流程

    private func prepare() async {
        let snapshot = await WindowCatalog.snapshot()
        guard var current = active else { return }
        let settings = context.settings.load(SwitcherSettings.self)
        let items = WindowOrdering.items(from: snapshot.records, appRecency: appRecency(), settings: settings)
        guard !items.isEmpty else {
            finish(confirm: false)
            return
        }
        let canCapture = settings.showThumbnails && context.permissions.isGranted(.screenRecording)
        var session = SwitcherSession(items: items, trigger: current.trigger, reverse: current.reverse)
        session.columns = Self.columns(for: items.count, thumbnails: canCapture)
        current.session = session
        current.elements = snapshot.elements
        // 立即开始截图（不等面板显示），面板出现时大多已经截好
        if canCapture {
            loadThumbnails(for: items)
        }
        let pending = current.pending
        current.pending = []
        active = current
        for event in pending where active != nil {
            handle(event)
        }
        guard let ready = active?.session else { return }
        // 用户在窗口列表准备好之前就松手了：直接切到上一个窗口，不显示面板
        if ready.isReleased(currentModifiers: ModifierState.current) {
            finish(confirm: true)
            return
        }
        scheduleShow(after: settings.showDelay, thumbnails: canCapture)
        startWatchdog()
    }

    private func handle(_ event: KeyEvent) {
        guard var current = active else { return }
        guard var session = current.session else {
            current.pending.append(event)
            active = current
            return
        }
        let action = session.handle(event)
        current.session = session
        active = current
        apply(action)
    }

    private func apply(_ action: SwitcherSession.Action) {
        switch action {
        case .none: syncModel()
        case .confirm: finish(confirm: true)
        case .cancel: finish(confirm: false)
        case let .closeWindow(item):
            WindowActions.close(element: element(for: item))
            removeItems { $0.id == item.id }
        case let .minimizeWindow(item):
            WindowActions.minimize(element: element(for: item))
            removeItems { $0.id == item.id }
        case let .hideApp(item):
            WindowActions.hide(pid: item.pid)
            removeItems { $0.pid == item.pid }
        case let .quitApp(item):
            WindowActions.quit(pid: item.pid)
            removeItems { $0.pid == item.pid }
        }
    }

    private func finish(confirm: Bool) {
        guard let current = active else { return }
        active = nil
        current.keyboard.end()
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        if confirm, let target = current.session?.selected {
            WindowActions.focus(
                target,
                element: target.windowID.flatMap { current.elements[$0]?.element },
                logger: context.logger,
            )
        }
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: 面板

    private func scheduleShow(after delay: Double, thumbnails: Bool) {
        tasks.append(Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.showPanel(thumbnails: thumbnails)
        })
    }

    private func showPanel(thumbnails showThumbnails: Bool) {
        guard let session = active?.session else { return }
        model.showThumbnails = showThumbnails
        model.columns = session.columns
        model.items = session.items
        model.selectedIndex = session.selectedIndex
        model.hoveredID = nil
        // 先用缓存（本次已截好的，或上一次的截图），避免先显示图标再跳成截图
        model.thumbnails = Dictionary(
            session.items.compactMap { item in item.windowID.flatMap(thumbnails.image(for:)).map { (item.id, $0) } },
            uniquingKeysWith: { first, _ in first },
        )
        for pid in Set(session.items.map(\.pid)) where model.icons[pid] == nil {
            model.icons[pid] = NSRunningApplication(processIdentifier: pid)?.icon
        }
        let panel = FloatingPanel(rootView: SwitcherPanelView(model: model))
        panel.level = .popUpMenu
        panel.place(relativeX: 0.5, relativeY: 0.5)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    /// 网格列数：尽量排成矩形，且不超过鼠标所在屏幕的宽度。
    private static func columns(for count: Int, thumbnails: Bool) -> Int {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let width = screen?.visibleFrame.width ?? 1200
        let maxColumns = SwitcherPanelView.maxColumns(screenWidth: width, thumbnails: thumbnails)
        return SwitcherLayout.columns(count: count, maxColumns: maxColumns)
    }

    private func loadThumbnails(for items: [SwitcherItem]) {
        let ids = items.compactMap(\.windowID)
        thumbnails.retain(only: ids)
        let byWindow = Dictionary(
            items.compactMap { item in item.windowID.map { ($0, item.id) } },
            uniquingKeysWith: { first, _ in first },
        )
        tasks.append(Task { [weak self] in
            for await (windowID, image) in ThumbnailLoader.load(windowIDs: ids) {
                guard let self, let id = byWindow[windowID] else { continue }
                let picture = NSImage(cgImage: image, size: .zero)
                self.thumbnails.store(picture, for: windowID)
                // 面板已显示时就地替换（格子尺寸固定，不会跳动）；未显示时由 showPanel 从缓存读取
                if self.panel != nil {
                    self.model.thumbnails[id] = picture
                }
            }
        })
    }

    private func syncModel() {
        guard let session = active?.session else { return }
        model.items = session.items
        model.selectedIndex = session.selectedIndex
    }

    private func select(_ index: Int) {
        guard var current = active, var session = current.session else { return }
        session.select(index)
        current.session = session
        active = current
        syncModel()
    }

    private func removeItems(where predicate: (SwitcherItem) -> Bool) {
        guard var current = active, var session = current.session else { return }
        session.remove(where: predicate)
        current.session = session
        active = current
        if session.items.isEmpty {
            finish(confirm: false)
        } else {
            syncModel()
        }
    }

    private func element(for item: SwitcherItem) -> AXUIElement? {
        item.windowID.flatMap { active?.elements[$0]?.element }
    }

    // MARK: 兜底

    private func startWatchdog() {
        let started = ContinuousClock.now
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.releasePollInterval)
                guard let self, let session = self.active?.session else { return }
                if ContinuousClock.now - started > Self.maxSessionDuration {
                    self.context.logger.warning("切换会话超时，自动取消")
                    self.finish(confirm: false)
                    return
                }
                if session.isReleased(currentModifiers: ModifierState.current) {
                    self.finish(confirm: true)
                    return
                }
            }
        })
    }
}
