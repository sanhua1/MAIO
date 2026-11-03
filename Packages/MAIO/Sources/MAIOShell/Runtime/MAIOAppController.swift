import AppKit
import MAIOCore
import MAIOKit

/// App 组合根：App 壳只需要创建它并调用 `start()`。
@MainActor
public final class MAIOAppController {
    let runtime: MAIORuntime
    let overlay = HUDOverlay()
    private var menuBar: MenuBarController?
    private lazy var settingsWindow = SettingsWindowController(controller: self)

    public init(catalog: [any Feature.Type]) {
        runtime = MAIORuntime(catalog: catalog, overlay: overlay)
    }

    public func start() async {
        CoreCommands.register(on: self)
        menuBar = MenuBarController(controller: self)
        await runtime.start()
        if runtime.input.status == .waitingForPermission {
            showSettings(pane: .permissions)
        }
        for issue in runtime.config.issues {
            overlay.showError(issue)
        }
    }

    public func stop() async {
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
