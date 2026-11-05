import Foundation
import MAIOKit
import os
import SwiftUI

/// 启动器：⌘空格弹出搜索框，搜应用（支持拼音、首字母，常用的排前面）、文件（Everything 式全盘索引）、
/// MAIO 命令 / 系统操作 / 系统设置面板、网页搜索；Tab 切换来源。见 docs/specs/M7-launcher.md。
@MainActor
public final class LauncherFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "launcher",
        displayName: "启动器",
        symbol: "magnifyingglass",
        summary: "⌘空格弹出搜索框：搜应用（支持拼音和首字母）、全盘搜文件（像 Everything）、MAIO 命令和系统设置、网页搜索，Tab 切换来源。",
        requiredPermissions: [],
        commands: LauncherCommands.descriptors,
        defaultBindings: [
            DefaultBinding(
                id: "launcher.default.show",
                trigger: .hotkey(KeyChord(keyCode: KeyCodes.code(named: "space") ?? 49, modifiers: .command)),
                command: LauncherCommands.show,
            ),
        ],
        // 开发中（M7），先默认关闭，免得替换掉其他用户的聚焦搜索
        enabledByDefault: false,
    )

    /// 打开面板时，应用列表超过这么久没刷新就在后台重新扫描
    static let catalogMaxAge: TimeInterval = 60

    private let context: any FeatureContext
    private var controller: LauncherController?
    private var usageStore: UsageStore?
    private var settingsTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var scannedAt: Date?
    private var fileIndex: FileIndexController?
    /// 系统设置的面板（和应用一起在后台扫描）
    private var settingsPanes: [SettingsPane] = []

    public init(context: any FeatureContext) {
        self.context = context
    }

    public func activate() async throws {
        let dataDirectory = try context.storage.dataDirectory()
        let store = UsageStore(dataDirectory: dataDirectory)
        let model = LauncherViewModel()
        model.usage = store.load()
        model.settings = context.settings.load(LauncherSettings.self)
        let settings = context.settings
        let logger = context.logger
        let commands = context.commands
        let overlay = context.overlay
        let controller = LauncherController(
            model: model,
            settings: { settings.load(LauncherSettings.self) },
            onRecord: { book in Self.save(book, to: store, logger: logger) },
            logger: { message in logger.error("\(message, privacy: .public)") },
            perform: { id in try await commands.perform(CommandID(rawValue: id)) },
            showError: { message in overlay.showError(message) },
        )
        LauncherCommands(context: context) { [weak self] source in
            guard let self, let controller = self.controller else { return }
            if !controller.isVisible {
                refreshAppsIfStale()
                refreshCommands()
                self.fileIndex?.checkAccess()
            }
            controller.toggle(source: source)
        }.register()
        usageStore = store
        self.controller = controller
        let fileIndex = FileIndexController(dataDirectory: dataDirectory, model: model)
        fileIndex.apply(model.settings)
        self.fileIndex = fileIndex
        rescanApps()
        watchSettings()
    }

    public func deactivate() async {
        settingsTask?.cancel()
        settingsTask = nil
        scanTask?.cancel()
        scanTask = nil
        controller?.tearDown()
        controller = nil
        fileIndex?.stop()
        fileIndex = nil
        usageStore = nil
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(LauncherSettingsView(settings: context.settings, status: fileIndex?.status))
    }

    /// 后台扫描应用目录，完成后替换列表
    private func rescanApps() {
        guard scanTask == nil else { return }
        scanTask = Task { [weak self] in
            let started = Date()
            let (apps, panes) = await Task.detached(priority: .userInitiated) {
                (AppCatalog.scan(), SettingsPaneCatalog.scan())
            }.value
            guard let self, !Task.isCancelled else { return }
            controller?.model.apps = apps
            settingsPanes = panes
            refreshCommands()
            scannedAt = Date()
            scanTask = nil
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            context.logger.info("启动器：扫描到 \(apps.count) 个应用、\(panes.count) 个设置面板，用时 \(elapsed) ms")
        }
    }

    /// 打开面板时调用：应用列表太旧就重新扫描（先用旧列表，扫完自动刷新）
    private func refreshAppsIfStale() {
        guard let scannedAt, Date().timeIntervalSince(scannedAt) > Self.catalogMaxAge else { return }
        rescanApps()
    }

    /// 命令列表：已启用的功能现在注册了哪些命令（功能随时可能被开关，所以每次打开面板都取一次）
    private func refreshCommands() {
        controller?.model.commands = CommandList.items(
            maio: context.commands.availableCommands(), panes: settingsPanes, own: Self.manifest.id,
        )
    }

    private func watchSettings() {
        let changes = context.settings.changes(LauncherSettings.self)
        settingsTask = Task { [weak self] in
            for await value in changes {
                self?.controller?.model.settings = value
                self?.controller?.model.refresh(resetSelection: false)
                self?.fileIndex?.apply(value)
            }
        }
    }

    private static func save(_ book: UsageBook, to store: UsageStore, logger: Logger) {
        do {
            try store.save(book)
        } catch {
            logger.error("保存常用记录失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}
