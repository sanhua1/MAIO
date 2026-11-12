import AppKit
import MAIOKit
import SwiftUI

/// 剪贴板历史（参考 Windows 上的 Ditto）：⌃V 在光标处弹出，默认选中最近一条，回车粘贴。
@MainActor
public final class ClipboardFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "clipboard",
        displayName: "剪贴板",
        symbol: "list.clipboard",
        summary: "记录复制过的文字、图片和文件。按 ⌃V 在光标处弹出历史，回车粘贴。",
        // 模拟 ⌘V 粘贴、读取光标位置需要辅助功能权限
        requiredPermissions: [.accessibility],
        commands: ClipboardCommands.descriptors,
        defaultBindings: [
            DefaultBinding(
                id: "clipboard.default.show",
                trigger: .hotkey(KeyChord(keyCode: KeyCodes.code(named: "v") ?? 9, modifiers: .control)),
                command: ClipboardCommands.show,
            ),
        ],
        enabledByDefault: true,
    )

    /// 每保存这么多次检查一次存储上限
    static let enforceEvery = 20

    private let context: any FeatureContext
    private var store: ClipStore?
    private var monitor: PasteboardMonitor?
    private var panel: ClipboardPanelController?
    private var imageText: ImageTextIndexer?
    private var settingsTask: Task<Void, Never>?
    private var insertsSinceEnforce = 0

    public init(context: any FeatureContext) {
        self.context = context
    }

    public func activate() async throws {
        let store = try ClipStore(directory: context.storage.dataDirectory())
        let monitor = PasteboardMonitor { [weak self] payload, source in self?.record(payload, source: source) }
        let model = ClipboardViewModel(store: store)
        let settings = context.settings
        let logger = context.logger
        let panel = ClipboardPanelController(model: model, dependencies: .init(
            store: store, paster: Paster(poster: context.input.poster), monitor: monitor,
            settings: { settings.load(ClipboardSettings.self) },
            logger: { message in logger.error("\(message, privacy: .public)") },
            commands: context.commands,
        ))
        ClipboardCommands(context: context, panel: panel).register()
        self.store = store
        self.monitor = monitor
        self.panel = panel
        imageText = ImageTextIndexer(store: store) { message in logger.info("\(message, privacy: .public)") }
        // 新复制的图片、升级前的旧图片都在后台识别文字（开关打开时，apply 里开始）
        apply(settings.load(ClipboardSettings.self))
        monitor.start()
        watchSettings()
        // 升级前保存的图片文件没有缩略图：原文件还在的补一份，旧记录也能看到预览
        Task { [weak self] in
            if let count = try? await store.backfillFileThumbnails(), count > 0 {
                logger.info("为 \(count) 个文件条目补了缩略图")
                // 补了缩略图的图片文件也要识别文字
                if settings.load(ClipboardSettings.self).searchImageText {
                    self?.imageText?.start()
                }
            }
        }
        try await store.enforce(limit: settings.load(ClipboardSettings.self).storageLimit.bytes)
        // macOS 15.4 起读取剪贴板可能需要用户授权（见 ADR-0010），记录当前状态方便排查
        context.logger.info("剪贴板读取权限：\(NSPasteboard.general.accessBehavior.rawValue)（0 默认 1 询问 2 允许 3 拒绝）")
    }

    public func deactivate() async {
        settingsTask?.cancel()
        settingsTask = nil
        monitor?.stop()
        monitor = nil
        imageText?.stop()
        imageText = nil
        panel?.tearDown()
        panel = nil
        store = nil
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(ClipboardSettingsView(settings: context.settings, store: store))
    }

    private func record(_ payload: ClipPayload, source: String?) {
        guard let store else { return }
        insertsSinceEnforce += 1
        let enforce = insertsSinceEnforce >= Self.enforceEvery
        if enforce {
            insertsSinceEnforce = 0
        }
        let limit = context.settings.load(ClipboardSettings.self).storageLimit.bytes
        let logger = context.logger
        let settings = context.settings
        Task { [weak self] in
            do {
                let item = try await store.insert(payload, source: source)
                if item.kind == .image || item.hasThumbnail, settings.load(ClipboardSettings.self).searchImageText {
                    self?.imageText?.start()
                }
                if enforce {
                    try await store.enforce(limit: limit)
                }
            } catch {
                logger.error("保存剪贴板失败：\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func watchSettings() {
        let changes = context.settings.changes(ClipboardSettings.self)
        settingsTask = Task { [weak self] in
            for await value in changes {
                self?.apply(value)
                if let store = self?.store {
                    _ = try? await store.enforce(limit: value.storageLimit.bytes)
                }
            }
        }
    }

    private func apply(_ settings: ClipboardSettings) {
        monitor?.options = PasteboardMonitor.Options(
            recordRichText: settings.recordRichText, recordImages: settings.recordImages, recordFiles: settings.recordFiles,
        )
        if settings.searchImageText {
            imageText?.start()
        } else {
            imageText?.stop()
        }
    }
}
