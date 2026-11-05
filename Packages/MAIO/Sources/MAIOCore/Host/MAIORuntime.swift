import Foundation
import MAIOKit
import Observation

/// 运行时组合：把配置、命令总线、绑定、输入引擎、功能宿主连接起来。
/// App 壳（MAIOShell）创建唯一一个实例。
@MainActor
public final class MAIORuntime {
    public let config: ConfigStore
    public let commandBus: CommandBus
    public let bindings: BindingStore
    public let input: InputEngine
    public let host: FeatureHost
    public let permissions: SystemPermissions
    public let events: WorkspaceEvents
    public let systemShortcuts: SystemShortcutManager
    /// 各功能登记占用的按键（ADR-0018）
    public let reservations = ShortcutReservations()

    public init(
        catalog: [any Feature.Type],
        overlay: any OverlayService,
        configRoot: URL = ConfigStore.defaultRoot(),
        systemShortcutStore: any SystemShortcutStore = MacSystemShortcutStore(),
    ) {
        let config = ConfigStore(root: configRoot)
        let commandBus = CommandBus()
        let bindings = BindingStore(config: config)
        let permissions = SystemPermissions()
        let events = WorkspaceEvents()
        let input = InputEngine { binding in
            commandBus.fire(binding.command, arguments: binding.arguments, source: binding.hotkeySource)
        }
        self.config = config
        systemShortcuts = SystemShortcutManager(store: systemShortcutStore, config: config)
        self.commandBus = commandBus
        self.bindings = bindings
        self.permissions = permissions
        self.events = events
        self.input = input
        let commands = catalog.flatMap { type in type.manifest.commands }
        let shortcuts = FeatureShortcutDirectory.Sources(
            bindings: bindings, systemShortcuts: systemShortcuts, reservations: reservations,
            commandTitle: { id in commands.first { $0.id == id }?.title ?? id.rawValue },
        )
        host = FeatureHost(
            catalog: catalog,
            services: .init(
                config: config, commandBus: commandBus, input: input,
                permissions: permissions, overlay: overlay, events: events, shortcuts: shortcuts,
            ),
        )
        commandBus.onFailure = { id, error in
            overlay.showError("\(id)：\(error.localizedDescription)")
        }
    }

    /// 启动顺序：出厂绑定 → 功能 → 快捷键表 → 输入引擎。
    public func start() async {
        bindings.seed(host.manifests.flatMap(\.defaultBindings))
        bindings.onChange = { [weak self] in self?.rebuildHotkeys() }
        commandBus.addChangeHandler { [weak self] in self?.rebuildHotkeys() }
        events.onFrontmostChange { [weak self] bundleID in self?.input.updateFrontmost(bundleID) }
        await host.startAll()
        rebuildHotkeys()
        input.start()
    }

    public func stop() async {
        input.stop()
        await host.stopAll()
    }

    /// 所有命令的描述（含未启用功能声明的命令），供绑定编辑器使用。
    public var allCommands: [(feature: FeatureManifest, commands: [CommandDescriptor])] {
        host.manifests.map { ($0, $0.commands) }
    }

    private func rebuildHotkeys() {
        input.updateBindings(HotkeyTable(bindings: bindings.bindings, isCommandAvailable: commandBus.isAvailable))
    }
}

private extension CommandBinding {
    var hotkeySource: CommandSource {
        switch trigger {
        case let .hotkey(chord): .hotkey(bindingID: id, chord: chord)
        }
    }
}
