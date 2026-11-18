import MAIOKit
import SwiftUI

/// 按键映射（原名"按键管理"，docs/specs/M8-keys.md，ADR-0022、0023）：设备级修饰键（写进系统的修饰键设置）、全局的 Caps 分层、全局改键、鼠标侧键、按 App 改修饰键（ADR-0026）。
@MainActor
public final class KeysFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "keys",
        displayName: "按键映射",
        symbol: "keyboard",
        summary: """
        让键盘和鼠标按你的习惯工作：
        • Super Caps：按住 Caps Lock，键盘上的键临时变成方向键、翻页等第二套功能
        • 键盘重映射：为每个键盘单独调换 ⌘ ⌃ ⌥ Fn 等修饰键的位置
        • 其他改键：把任意键或鼠标侧键改成别的键、组合键，或直接执行 MAIO 命令
        • 按 App 改键：在指定 App（例如游戏）里调换 ⌘ ⌃ ⌥ Fn
        """,
        requiredPermissions: [.accessibility, .inputMonitoring],
        commands: [],
        defaultBindings: [],
        enabledByDefault: false,
    )

    private let context: any FeatureContext
    private let keyboards = HIDKeyboards()
    private var remaps: RemapController?
    private var appModifiers: AppModifierController?
    private var settingsTask: Task<Void, Never>?

    public init(context: any FeatureContext) {
        self.context = context
    }

    public func activate() async throws {
        let remaps = RemapController(context: context, keyboards: keyboards)
        let appModifiers = AppModifierController(context: context, keyboards: keyboards)
        let settings = context.settings.load(KeysSettings.self)
        remaps.apply(settings)
        appModifiers.update(settings.appModifierRules)
        self.remaps = remaps
        self.appModifiers = appModifiers
        let changes = context.settings.changes(KeysSettings.self)
        settingsTask = Task { [weak self] in
            for await settings in changes {
                self?.remaps?.apply(settings)
                self?.appModifiers?.update(settings.appModifierRules)
            }
        }
    }

    public func deactivate() async {
        settingsTask?.cancel()
        settingsTask = nil
        remaps?.stop()
        remaps = nil
        appModifiers?.stop()
        appModifiers = nil
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(KeysSettingsView(context: context, remaps: remaps, appModifiers: appModifiers))
    }
}
