import AppKit
import MAIOKit

/// 宿主自身提供的命令（所有者为 `maio`）。
@MainActor
enum CoreCommands {
    static let openSettings: CommandID = "maio.openSettings"
    static let quit: CommandID = "maio.quit"
    static let restoreSystemShortcuts: CommandID = "maio.restoreSystemShortcuts"

    static let manifest = FeatureManifest(
        id: .core,
        displayName: "MAIO",
        symbol: "square.grid.2x2",
        summary: "MAIO 自身的命令",
        commands: [
            CommandDescriptor(id: openSettings, title: "打开 MAIO 设置"),
            CommandDescriptor(id: quit, title: "退出 MAIO"),
            CommandDescriptor(
                id: restoreSystemShortcuts,
                title: "恢复 MAIO 禁用的全部系统快捷键",
                summary: "把 MAIO 禁用过的系统快捷键全部恢复为原始设置",
            ),
        ],
    )

    static func register(on controller: MAIOAppController) {
        let bus = controller.runtime.commandBus
        bus.register(manifest.commands[0], owner: .core) { [weak controller] _ in
            controller?.showSettings()
            return .null
        }
        bus.register(manifest.commands[1], owner: .core) { _ in
            NSApp.terminate(nil)
            return .null
        }
        bus.register(manifest.commands[2], owner: .core) { [weak controller] _ in
            guard let controller else { return .null }
            let manager = controller.runtime.systemShortcuts
            let count = manager.backups.count
            manager.restoreAll()
            controller.overlay.showHUD(
                count == 0 ? "没有需要恢复的系统快捷键" : "已恢复 \(count) 个系统快捷键",
                symbol: "arrow.uturn.backward",
            )
            return .null
        }
    }
}
