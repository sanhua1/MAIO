import MAIOKit
import SwiftUI

/// 按键管理（docs/specs/M8-keys.md，ADR-0022、0023）：设备级修饰键（写进系统的修饰键设置）、全局的 Caps 分层、全局改键、鼠标侧键。
@MainActor
public final class KeysFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "keys",
        displayName: "按键管理",
        symbol: "keyboard",
        summary: "给每个键盘单独改修饰键（例如把 Mac 自带键盘改成 ⌘ ⌃ Fn ⌥），直接写进系统设置；Caps 变成分层键：按住 Caps 时整个键盘换一层（默认 WASD 方向键），单按什么都不发生；全局改键（Home → 行首等）和鼠标侧键改键。",
        requiredPermissions: [.accessibility, .inputMonitoring],
        commands: [],
        defaultBindings: [],
        enabledByDefault: false,
    )

    private let context: any FeatureContext
    private let keyboards = HIDKeyboards()
    private var remaps: RemapController?
    private var settingsTask: Task<Void, Never>?

    public init(context: any FeatureContext) {
        self.context = context
    }

    public func activate() async throws {
        let remaps = RemapController(context: context, keyboards: keyboards)
        remaps.apply(context.settings.load(KeysSettings.self))
        self.remaps = remaps
        let changes = context.settings.changes(KeysSettings.self)
        settingsTask = Task { [weak self] in
            for await settings in changes {
                self?.remaps?.apply(settings)
            }
        }
    }

    public func deactivate() async {
        settingsTask?.cancel()
        settingsTask = nil
        remaps?.stop()
        remaps = nil
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(KeysSettingsView(context: context, remaps: remaps))
    }
}
