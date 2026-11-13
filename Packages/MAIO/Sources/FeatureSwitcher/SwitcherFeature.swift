import MAIOKit
import SwiftUI

/// 窗口切换（类似 Windows 的 Alt+Tab）。触发键可在「MAIO 快捷键」页自定义，默认 ⌥⇥。
@MainActor
public final class SwitcherFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "switcher",
        displayName: "窗口切换",
        symbol: "rectangle.on.rectangle",
        summary: "按住 ⌥ 再按 ⇥ 在所有窗口之间切换（触发键可自定义，例如 ⌘⇥）。",
        requiredPermissions: [.accessibility],
        commands: SwitcherCommands.descriptors,
        defaultBindings: [
            DefaultBinding(
                id: "switcher.default.show",
                trigger: .hotkey(KeyChord(keyCode: KeyCodes.tab, modifiers: .option)),
                command: SwitcherCommands.show,
            ),
            DefaultBinding(
                id: "switcher.default.showReverse",
                trigger: .hotkey(KeyChord(keyCode: KeyCodes.tab, modifiers: [.option, .shift])),
                command: SwitcherCommands.showReverse,
            ),
        ],
        enabledByDefault: true,
    )

    private let context: any FeatureContext
    private var controller: SwitcherController?
    private var recencyTask: Task<Void, Never>?
    /// 最近使用的 App（bundle ID，最近的在前），用于排列不在屏幕上的窗口
    private var appRecency: [String] = []

    public init(context: any FeatureContext) {
        self.context = context
    }

    public func activate() async throws {
        let controller = SwitcherController(context: context) { [weak self] in self?.appRecency ?? [] }
        SwitcherCommands(controller: controller).register(on: context.commands)
        self.controller = controller
        if let current = context.events.frontmostBundleID {
            appRecency = [current]
        }
        let changes = context.events.frontmostApplicationChanges()
        recencyTask = Task { [weak self] in
            for await bundleID in changes {
                guard let self, let bundleID else { continue }
                self.appRecency.removeAll { $0 == bundleID }
                self.appRecency.insert(bundleID, at: 0)
            }
        }
    }

    public func deactivate() async {
        recencyTask?.cancel()
        recencyTask = nil
        controller?.stop()
        controller = nil
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(SwitcherSettingsView(settings: context.settings, permissions: context.permissions))
    }
}
