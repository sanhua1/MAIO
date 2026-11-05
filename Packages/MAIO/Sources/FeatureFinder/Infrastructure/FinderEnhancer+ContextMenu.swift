import AppKit
import MAIOKit

/// 右键菜单（Finder Sync 扩展）：写菜单配置给扩展；执行扩展通过 maio:// URL 交过来的动作。
extension FinderEnhancer {
    static let contextMenuFile = "context-menu.json"

    var templates: TemplateStore? {
        (try? context.storage.dataDirectory()).map(TemplateStore.init(dataDirectory:))
    }

    /// 设置或模板变化后调用：重写扩展读取的菜单配置
    func writeContextMenuConfig() {
        guard let directory = try? context.storage.dataDirectory(), let templates else { return }
        templates.seedIfNeeded()
        let config = ContextMenuConfig.make(enabled: settings.contextMenuActions, templates: templates.list())
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: directory.appending(path: Self.contextMenuFile), options: .atomic)
    }

    /// 扩展交过来的动作。target 是右键所在的文件夹，items 是选中的文件（文件夹以 / 结尾）
    func performContextMenu(action: String, target: URL?, items: [URL]) async {
        if action.hasPrefix(ContextMenuConfig.templatePrefix) {
            await newFile(fromTemplate: String(action.dropFirst(ContextMenuConfig.templatePrefix.count)), in: target)
            return
        }
        switch ContextMenuAction(rawValue: action) {
        case .cut:
            await perform(.cut(copy: resolved(FinderActions.copy)))
        case .paste:
            paste()
        case .copyPath:
            let paths = (items.isEmpty ? target.map { [$0] } ?? [] : items).map { $0.path(percentEncoded: false) }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
            context.overlay.showHUD(paths.count > 1 ? "已复制 \(paths.count) 个路径" : "已复制路径", symbol: "link")
        case .openTerminal:
            let folder = items.count == 1 && items[0].hasDirectoryPath ? items[0] : target
            if let folder {
                await open(folder, terminal: settings.terminalBundleID)
            }
        case .toggleHidden:
            context.input.poster.post(.keyStroke(KeyChord(keyCode: 47, modifiers: [.command, .shift])))
        case .newFile, nil:
            break
        }
    }

    /// 粘贴：剪切过就移动（Finder 的"将项目移到这里"），否则普通粘贴。右键时 Finder 在前台，直接发按键
    private func paste() {
        if filter.isCutPending {
            filter.setCutPending(false)
            context.input.poster.post(.keyStroke(resolved(FinderActionID.paste.info.target)))
        } else {
            let paste = FinderActionTarget.menu(
                MenuPath(["编辑", "粘贴项目"], ["编辑", "粘贴"], ["Edit", "Paste Item"], ["Edit", "Paste"]),
                fallback: KeyChord(keyCode: FinderKeymap.Key.v, modifiers: .command),
            )
            context.input.poster.post(.keyStroke(resolved(paste)))
        }
    }

    private func resolved(_ target: FinderActionTarget) -> KeyChord {
        FinderSettings.resolve(target, menu: menu.items, overrides: menu.overrides)
            ?? KeyChord(keyCode: FinderKeymap.Key.c, modifiers: .command)
    }

    /// 从模板新建：先在临时目录复制一份（起好不重名的名字），再让 Finder 移进目标文件夹并进入重命名
    private func newFile(fromTemplate template: String, in target: URL?) async {
        guard let templates, let target else { return }
        let source = templates.url(of: template)
        switch await FinderScripting.uniqueName(FileTemplates.newFileName(for: template), in: target) {
        case let .success(name):
            let manager = FileManager.default
            let staging = manager.temporaryDirectory.appending(path: "maio-new-\(UUID().uuidString)", directoryHint: .isDirectory)
            let file = staging.appending(path: name)
            do {
                try manager.createDirectory(at: staging, withIntermediateDirectories: true)
                try manager.copyItem(at: source, to: file)
            } catch {
                context.overlay.showError("模板「\(template)」读取失败：\(error.localizedDescription)")
                return
            }
            defer { try? manager.removeItem(at: staging) }
            if case let .failure(error) = await FinderScripting.moveIn(file, to: target) {
                context.overlay.showError(error.message)
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
            context.input.poster.post(.keyStroke(KeyChord(keyCode: FinderKeymap.Key.returnKey, modifiers: [])))
        case let .failure(error):
            context.overlay.showError(error.message)
        }
    }
}
