import MAIOKit
import SwiftUI

/// 翻译：选中文字按 ⌥Q 翻译，或打开输入框翻译。多个翻译源并行，大模型逐字显示。
@MainActor
public final class TranslateFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "translate",
        displayName: "翻译",
        symbol: "character.bubble",
        summary: "选中文字按 ⌥Q 翻译；没有选中时打开输入框。支持 Google、必应、DeepSeek 等多个翻译源同时翻译。",
        // 读取选中文字（辅助功能接口、模拟 ⌘C）需要辅助功能权限
        requiredPermissions: [.accessibility],
        commands: TranslateCommands.descriptors,
        defaultBindings: [
            DefaultBinding(
                id: "translate.default.show",
                trigger: .hotkey(KeyChord(keyCode: KeyCodes.code(named: "q") ?? 12, modifiers: .option)),
                command: TranslateCommands.show,
            ),
        ],
        enabledByDefault: true,
    )

    private let context: any FeatureContext
    private let factory: ProviderFactory
    private let history: HistoryStore
    private var window: TranslateWindowController?

    public init(context: any FeatureContext) {
        self.context = context
        factory = ProviderFactory(secrets: context.secrets)
        history = HistoryStore(storage: context.storage, logger: context.logger)
    }

    public func activate() async throws {
        let settings = context.settings
        let logger = context.logger
        let model = TranslateViewModel(environment: TranslateViewModel.Environment(
            settings: { settings.load(TranslateSettings.self) },
            factory: factory,
            history: history,
        ))
        let window = TranslateWindowController(
            model: model,
            settings: { settings.load(TranslateSettings.self) },
            saveSettings: { settings.save($0) },
            logger: { message in logger.info("\(message, privacy: .public)") },
        )
        TranslateCommands(context: context, window: window).register()
        self.window = window
        factory.prewarm(settings.load(TranslateSettings.self).services)
    }

    public func deactivate() async {
        window?.tearDown()
        window = nil
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(TranslateSettingsView(
            settings: context.settings, secrets: context.secrets, factory: factory, history: history,
        ))
    }
}
