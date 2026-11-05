import MAIOKit

/// 命令处理：只做参数解析与调度，业务逻辑放在 Domain/。
@MainActor
struct LauncherCommands {
    static let show: CommandID = "launcher.show"
    static let showApps: CommandID = "launcher.showApps"

    static let descriptors: [CommandDescriptor] = [
        CommandDescriptor(
            id: show, title: "启动器",
            summary: "打开 / 关闭启动器：搜应用（支持拼音）、网页搜索。默认 ⌘空格（会接管系统聚焦的快捷键）",
        ),
        CommandDescriptor(id: showApps, title: "启动器（只搜应用）", summary: "打开启动器并直接进入“应用”来源"),
    ]

    let context: any FeatureContext
    /// 打开 / 关闭面板（参数：打开时的来源）
    let toggle: @MainActor (LauncherSource) -> Void

    func register() {
        let toggle = toggle
        context.commands.register(Self.descriptors[0]) { _ in toggle(.all) }
        context.commands.register(Self.descriptors[1]) { _ in toggle(.apps) }
    }
}
