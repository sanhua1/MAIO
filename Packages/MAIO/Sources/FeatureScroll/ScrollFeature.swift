import AppKit
import MAIOKit
import SwiftUI

/// 鼠标滚动：反转方向、平滑滚动、按 App 例外（替换 Mos）。
@MainActor
public final class ScrollFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "scroll",
        displayName: "鼠标滚动",
        symbol: "computermouse",
        summary: "反转鼠标滚轮方向、平滑滚动、⌘ + 滚轮缩放（模拟触控板捏合），可按 App 设置例外。触控板不受影响。",
        requiredPermissions: [.accessibility],
        commands: ScrollCommands.descriptors,
        enabledByDefault: true,
    )

    private let context: any FeatureContext
    private var filter: ScrollInputFilter?
    private var token: FilterToken?
    private var settingsTask: Task<Void, Never>?

    public init(context: any FeatureContext) {
        self.context = context
    }

    public func activate() async throws {
        let filter = ScrollInputFilter(config: currentConfig(), poster: context.input.poster)
        token = context.input.registerFilter(filter, for: .scrollWheel, stage: .smooth)
        self.filter = filter
        ScrollCommands(context: context).register()
        let changes = context.settings.changes(ScrollSettings.self)
        settingsTask = Task { [weak self] in
            for await _ in changes {
                guard let self else { return }
                self.filter?.update(self.currentConfig())
            }
        }
    }

    public func deactivate() async {
        settingsTask?.cancel()
        settingsTask = nil
        filter?.animator.stop()
        filter?.zoomer.stop()
        if let token {
            context.input.removeFilter(token)
        }
        token = nil
        filter = nil
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(ScrollSettingsView(settings: context.settings))
    }

    private func currentConfig() -> ScrollConfig {
        ScrollConfig(
            settings: context.settings.load(ScrollSettings.self),
            framesPerSecond: Self.framesPerSecond,
            ownBundleID: Bundle.main.bundleIdentifier,
        )
    }

    /// 所有屏幕中最高的刷新率（ProMotion / 高刷显示器为 120）。
    private static var framesPerSecond: Double {
        Double(NSScreen.screens.map(\.maximumFramesPerSecond).max() ?? 60)
    }
}
