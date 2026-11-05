import AppKit
import MAIOKit

/// 把改键过滤器、Finder 菜单快照、焦点监听、剪切状态、速查面板串起来（主线程）。
@MainActor
final class FinderEnhancer {
    let context: any FeatureContext
    let filter: FinderKeyFilter
    let menu = FinderMenuStore()
    let cheatSheet: FinderCheatSheet
    private let focus = FinderFocusMonitor()
    private var tasks: [Task<Void, Never>] = []
    /// 剪切时剪贴板的 changeCount；剪贴板再变就说明用户复制了别的东西，剪切作废
    private var cutChangeCount: Int?

    init(context: any FeatureContext) {
        self.context = context
        filter = FinderKeyFilter(config: .off)
        cheatSheet = FinderCheatSheet(menu: menu)
    }

    var settings: FinderSettings {
        context.settings.load(FinderSettings.self)
    }

    func start() {
        focus.onEditingChange = { [weak self] editing in self?.filter.setEditing(editing) }
        focus.onTick = { [weak self] in self?.validateCut() }
        applySettings()
        frontmostChanged(context.events.frontmostBundleID)
        let actions = filter.actions
        let frontmost = context.events.frontmostApplicationChanges()
        let changes = context.settings.changes(FinderSettings.self)
        tasks = [
            Task { [weak self] in
                for await action in actions {
                    await self?.perform(action)
                }
            },
            Task { [weak self] in
                for await bundleID in frontmost {
                    self?.frontmostChanged(bundleID)
                }
            },
            Task { [weak self] in
                for await _ in changes {
                    self?.applySettings()
                }
            },
            Task { [weak self] in
                await self?.refreshMenu()
            },
        ]
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
        filter.finish()
        focus.stop()
        cheatSheet.hide()
    }

    /// 重新读 Finder 菜单（改了原生快捷键、重启 Finder 后），并更新改键目标
    func refreshMenu() async {
        await menu.refresh()
        applySettings()
    }

    /// 设置或菜单变了：重建过滤器配置，重新登记占用的按键（快捷键页据此提示冲突）
    func applySettings() {
        let settings = settings
        filter.update(settings.keyConfig(menu: menu.items, overrides: menu.overrides))
        cheatSheet.delay = settings.cheatSheetDelay
        let finder = BindingScope.onlyIn([FinderKeymap.bundleID])
        context.shortcuts.reserve(FinderActionID.allCases.compactMap { action in
            settings.chord(for: action).map { ReservedShortcut(chord: $0, scope: finder, title: action.info.title) }
        })
        writeContextMenuConfig()
    }

    private func frontmostChanged(_ bundleID: String?) {
        let isFinder = bundleID == FinderKeymap.bundleID
        focus.setActive(isFinder)
        if isFinder {
            validateCut()
            Task { [weak self] in
                await self?.menu.refreshIfStale()
                self?.applySettings()
            }
        } else {
            cheatSheet.cancel()
        }
    }

    // MARK: 动作

    func perform(_ action: FinderAction) async {
        switch action {
        case let .cut(copy): await cut(copy: copy)
        case .newTextFile: await newTextFile()
        case .openTerminal: await openTerminal()
        case let .modifiers(modifiers): cheatSheet.modifiersChanged(modifiers, settings: settings)
        case .keyWhileCommand: cheatSheet.cancel()
        }
    }

    /// 剪切：发 Finder 的"拷贝"，剪贴板变了且里面有文件才算剪切成功（没选中东西时什么也不做）
    private func cut(copy: KeyChord) async {
        let pasteboard = NSPasteboard.general
        let before = pasteboard.changeCount
        context.input.poster.post(.keyStroke(copy))
        for _ in 0 ..< 25 {
            try? await Task.sleep(for: .milliseconds(20))
            guard pasteboard.changeCount != before else { continue }
            markCut(in: pasteboard)
            return
        }
    }

    /// 剪贴板里有文件时标记"待移动"（右键菜单的剪切也走这里）
    func markCut(in pasteboard: NSPasteboard = .general) {
        let count = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])?.count ?? 0
        guard count > 0 else { return }
        cutChangeCount = pasteboard.changeCount
        filter.setCutPending(true)
        let paste = settings.chord(for: .paste)?.displayString ?? "粘贴"
        context.overlay.showHUD("已剪切 \(count) 项，到目标位置按 \(paste) 移动", symbol: "scissors")
    }

    private func validateCut() {
        guard let cutChangeCount else { return }
        guard filter.isCutPending, NSPasteboard.general.changeCount == cutChangeCount else {
            filter.setCutPending(false)
            self.cutChangeCount = nil
            return
        }
    }

    func newTextFile() async {
        let name = settings.newFileName
        switch await FinderScripting.newFile(named: name.isEmpty ? FinderSettings.defaultValue.newFileName : name) {
        case .success:
            // 选中后发回车进入重命名（合成按键不经过改键过滤器）
            try? await Task.sleep(for: .milliseconds(150))
            context.input.poster.post(.keyStroke(KeyChord(keyCode: FinderKeymap.Key.returnKey, modifiers: [])))
        case let .failure(error):
            context.overlay.showError(error.message)
        }
    }

    func openTerminal() async {
        switch await FinderScripting.insertionFolder() {
        case let .success(folder):
            await open(folder, terminal: settings.terminalBundleID)
        case let .failure(error):
            context.overlay.showError(error.message)
        }
    }

    func open(_ folder: URL, terminal bundleID: String) async {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
        else { return }
        do {
            try await NSWorkspace.shared.open([folder], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } catch {
            context.overlay.showError("打不开终端：\(error.localizedDescription)")
        }
    }
}
