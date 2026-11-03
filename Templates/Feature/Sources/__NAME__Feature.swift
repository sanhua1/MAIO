import MAIOKit
import SwiftUI

/// TODO: 一句话说明这个功能做什么。
@MainActor
public final class __NAME__Feature: Feature {
    public static let manifest = FeatureManifest(
        id: "__ID__",
        displayName: "__NAME__",
        symbol: "puzzlepiece.extension",
        summary: "TODO: 一句话说明",
        requiredPermissions: [],
        commands: __NAME__Commands.descriptors,
        defaultBindings: [],
        enabledByDefault: false
    )

    private let context: any FeatureContext
    private var settings: __NAME__Settings

    public init(context: any FeatureContext) {
        self.context = context
        settings = context.settings.load(__NAME__Settings.self)
    }

    public func activate() async throws {
        __NAME__Commands(context: context).register()
    }

    public func deactivate() async {
        // 释放自己创建的窗口、Task、监听。命令和过滤器由宿主自动清理。
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(__NAME__SettingsView(settings: context.settings))
    }
}
