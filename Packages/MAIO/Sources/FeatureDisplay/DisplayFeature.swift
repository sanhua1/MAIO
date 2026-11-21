import MAIOKit
import SwiftUI

/// 外接显示器（docs/specs/M9-display.md，ADR-0028）：用 Mac 的音量键、亮度键通过 DDC/CI 调外接显示器的音量和亮度，
/// 菜单栏菜单里放亮度滑块。
@MainActor
public final class DisplayFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "display",
        displayName: "外接显示器",
        symbol: "display",
        summary: """
        像调 Mac 自己的屏幕和扬声器一样调外接显示器：
        • 音量键：声音从显示器出来（音箱接在显示器上）时，调显示器的音量
        • 亮度键：鼠标在外接显示器上时，调它的亮度
        • 菜单栏菜单里有外接显示器的亮度条、音量条
        """,
        requiredPermissions: [.accessibility],
        commands: [],
        defaultBindings: [],
        enabledByDefault: true,
    )

    private let context: any FeatureContext
    private var controller: DisplayController?
    private var settingsTask: Task<Void, Never>?

    public init(context: any FeatureContext) {
        self.context = context
    }

    public func activate() async throws {
        let controller = DisplayController(settings: context.settings.load(DisplaySettings.self), logger: context.logger)
        _ = context.input.registerMediaKeyFilter(controller.filter)
        controller.start()
        self.controller = controller
        let changes = context.settings.changes(DisplaySettings.self)
        settingsTask = Task { [weak self] in
            for await settings in changes {
                self?.controller?.apply(settings)
            }
        }
    }

    public func deactivate() async {
        settingsTask?.cancel()
        settingsTask = nil
        controller?.stop()
        controller = nil
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(DisplaySettingsView(settings: context.settings, controller: controller))
    }

    public func makeMenuBarView() -> AnyView? {
        guard let controller, !controller.menuDisplays.isEmpty else { return nil }
        return AnyView(DisplayMenuView(controller: controller))
    }
}
