import AppKit
import MAIOCore
import MAIOKit

/// App 组合根：App 壳只需要创建它并调用 `start()`。
@MainActor
public final class MAIOAppController {
    let runtime: MAIORuntime
    let overlay = HUDOverlay()
    private var menuBar: MenuBarController?
    private var mainMenu: MainMenu?
    private lazy var settingsWindow = SettingsWindowController(controller: self)
    let updater: Updater
    private let updatePrompt: UpdatePromptWindow

    public init(catalog: [any Feature.Type]) {
        runtime = MAIORuntime(catalog: catalog, overlay: overlay)
        updater = Updater(config: runtime.config, overlay: overlay)
        updatePrompt = UpdatePromptWindow(updater: updater)
        updater.onReady = { [updatePrompt] prepared in updatePrompt.show(prepared) }
    }

    public func start() async {
        CoreCommands.register(on: self)
        menuBar = MenuBarController(controller: self)
        // 标准快捷键（⌘C、⌘V、⌘A、⌘W…）靠主菜单分发，见 MainMenu
        mainMenu = MainMenu { [weak self] in self?.showSettings() }
        mainMenu?.install()
        await runtime.start()
        if runtime.input.status == .waitingForPermission {
            showSettings(pane: .general)
        }
        for issue in runtime.config.issues {
            overlay.showError(issue)
        }
        updater.start()
    }

    public func stop() async {
        updater.stop()
        await runtime.stop()
    }

    public func handle(url: URL) {
        guard let (id, arguments) = URLCommandRouter.parse(url) else {
            overlay.showError("无法识别的链接：\(url.absoluteString)")
            return
        }
        runtime.commandBus.fire(id, arguments: arguments, source: .url)
    }

    public func showSettings() {
        settingsWindow.show(pane: nil)
    }

    func showSettings(pane: SettingsPane) {
        settingsWindow.show(pane: pane)
    }

    /// 绑定编辑器使用：MAIO 自身命令 + 所有功能声明的命令。
    var commandCatalog: [FeatureManifest] {
        [CoreCommands.manifest] + runtime.host.manifests
    }
}
