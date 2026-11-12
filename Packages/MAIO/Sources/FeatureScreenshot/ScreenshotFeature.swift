import MAIOKit
import SwiftUI

/// 截图（替代 PixPin）：⌥F1 冻结屏幕后框选，自动识别窗口和控件、取色，复制或保存，并写入截图历史。
/// 需求和分阶段计划见 docs/specs/M5-screenshot.md。
@MainActor
public final class ScreenshotFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "screenshot",
        displayName: "截图",
        symbol: "camera.viewfinder",
        summary: "按 ⌥F1 冻结屏幕后框选，可以标注、取色、贴图。截图自动复制并保存在截图历史里；⌥F2 把剪贴板内容贴到屏幕上。",
        // 识别控件只在有辅助功能权限时可用，不作为必需权限
        requiredPermissions: [.screenRecording],
        commands: ScreenshotCommands.descriptors,
        defaultBindings: [
            DefaultBinding(
                id: "screenshot.default.capture",
                trigger: .hotkey(KeyChord(keyCode: KeyCodes.code(named: "f1") ?? 122, modifiers: .option)),
                command: ScreenshotCommands.capture,
            ),
            DefaultBinding(
                id: "screenshot.default.fullScreen",
                trigger: .hotkey(KeyChord(keyCode: KeyCodes.code(named: "f1") ?? 122, modifiers: [.command, .option])),
                command: ScreenshotCommands.fullScreen,
            ),
            DefaultBinding(
                id: "screenshot.default.pinClipboard",
                trigger: .hotkey(KeyChord(keyCode: KeyCodes.code(named: "f2") ?? 120, modifiers: .option)),
                command: ScreenshotCommands.pinClipboard,
            ),
        ],
        enabledByDefault: true,
    )

    private let context: any FeatureContext
    private var controller: ScreenshotController?
    private var history: ScreenshotHistoryStore?
    private var settingsTask: Task<Void, Never>?

    public init(context: any FeatureContext) {
        self.context = context
    }

    public func activate() async throws {
        let history: ScreenshotHistoryStore?
        do {
            history = try ScreenshotHistoryStore(directory: context.storage.dataDirectory())
        } catch {
            history = nil
            context.logger.error("截图历史不可用：\(error.localizedDescription, privacy: .public)")
        }
        let controller = ScreenshotController(context: context, history: history)
        ScreenshotCommands(context: context, controller: controller).register()
        controller.prepare()
        self.controller = controller
        self.history = history
        // 修改历史上限后立即清理
        let changes = context.settings.changes(ScreenshotSettings.self)
        var limit = context.settings.load(ScreenshotSettings.self).historyLimit
        settingsTask = Task { [weak controller] in
            for await value in changes where value.historyLimit != limit {
                limit = value.historyLimit
                controller?.enforceHistoryLimit()
            }
        }
    }

    public func deactivate() async {
        settingsTask?.cancel()
        settingsTask = nil
        controller?.tearDown()
        controller = nil
        history = nil
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(ScreenshotSettingsView(
            settings: context.settings, permissions: context.permissions, history: history,
            openHistory: { [weak controller] in controller?.showHistory() },
        ))
    }
}
