import MAIOKit
import SwiftUI

/// Finder 增强：Windows 资源管理器式的按键和操作，以及 Finder 的隐藏设置（ADR-0017，不注入 Finder）。
@MainActor
public final class FinderFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "finder",
        displayName: "Finder 增强",
        symbol: "folder.badge.gearshape",
        summary: "让 Finder 用起来像 Windows 资源管理器：Finder 的隐藏设置一键开关；原生快捷键一览和重设；补上剪切、回车打开、F2 重命名、新建文件等，每一项都能开关、改键，冲突实时提示。长按 ⌘ 显示速查面板。",
        requiredPermissions: [.accessibility],
        commands: FinderCommands.descriptors,
        defaultBindings: [],
        enabledByDefault: false,
    )

    private let context: any FeatureContext
    private var enhancer: FinderEnhancer?
    private var token: FilterToken?

    public init(context: any FeatureContext) {
        self.context = context
    }

    public func activate() async throws {
        let enhancer = FinderEnhancer(context: context)
        token = context.input.registerKeyFilter(enhancer.filter)
        enhancer.start()
        FinderCommands(context: context, enhancer: enhancer).register()
        self.enhancer = enhancer
    }

    public func deactivate() async {
        enhancer?.stop()
        enhancer = nil
        if let token {
            context.input.removeFilter(token)
        }
        token = nil
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(FinderSettingsView(context: context, enhancer: enhancer))
    }
}
