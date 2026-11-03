import MAIOKit
import SwiftUI

/// 通用系统动作：打开 App / URL、运行 Shell / AppleScript / 快捷指令、发送按键。
@MainActor
public final class SystemActionsFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "system",
        displayName: "系统动作",
        symbol: "command.square",
        summary: "把快捷键绑定到打开 App、打开网址、运行脚本、快捷指令或发送其他按键。",
        commands: SystemActionsCommands.descriptors,
        defaultBindings: [
            DefaultBinding(
                id: "system.default.activityMonitor",
                trigger: .hotkey(KeyChord(keyCode: 0, modifiers: .function)),
                command: SystemActionsCommands.openApp,
                arguments: ["app": "com.apple.ActivityMonitor"],
            ),
        ],
    )

    private let context: any FeatureContext
    private let runner = ProcessRunner()

    public init(context: any FeatureContext) {
        self.context = context
    }

    public func activate() async throws {
        SystemActionsCommands(context: context, runner: runner).register()
    }

    public func deactivate() async {
        await runner.cancelAll()
    }
}
