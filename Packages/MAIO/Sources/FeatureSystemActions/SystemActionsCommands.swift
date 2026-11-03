import AppKit
import MAIOKit

/// 命令处理：只做参数解析和调度，具体逻辑在 Domain / Infrastructure。
@MainActor
struct SystemActionsCommands {
    static let openApp: CommandID = "system.openApp"
    static let openURL: CommandID = "system.openURL"
    static let runShell: CommandID = "system.runShell"
    static let runAppleScript: CommandID = "system.runAppleScript"
    static let runShortcut: CommandID = "system.runShortcut"
    static let sendKeys: CommandID = "system.sendKeys"

    static let descriptors: [CommandDescriptor] = [
        CommandDescriptor(
            id: openApp, title: "打开 App", summary: "已在运行则切换到前台",
            parameters: [ParameterSpec(
                key: "app",
                title: "App",
                kind: .application,
                placeholder: "com.apple.ActivityMonitor 或 /Applications/xxx.app",
            )],
        ),
        CommandDescriptor(
            id: openURL, title: "打开网址或文件",
            parameters: [ParameterSpec(key: "url", title: "地址", kind: .text, placeholder: "https://… 或 ~/Downloads")],
        ),
        CommandDescriptor(
            id: runShell, title: "运行 Shell 命令", summary: "使用 /bin/zsh -lc 在后台执行，失败时提示",
            parameters: [
                ParameterSpec(key: "script", title: "命令", kind: .multilineText),
                ParameterSpec(key: "showOutput", title: "完成后显示输出", kind: .bool, isRequired: false, defaultValue: false),
            ],
        ),
        CommandDescriptor(
            id: runAppleScript, title: "运行 AppleScript",
            parameters: [ParameterSpec(key: "source", title: "脚本", kind: .multilineText)],
        ),
        CommandDescriptor(
            id: runShortcut, title: "运行快捷指令",
            parameters: [ParameterSpec(key: "name", title: "快捷指令名称", kind: .text)],
        ),
        CommandDescriptor(
            id: sendKeys, title: "发送按键", summary: "键位重映射：触发后发送另一组按键",
            parameters: [ParameterSpec(key: "keys", title: "按键", kind: .keyChord, placeholder: "cmd+shift+4")],
        ),
    ]

    let context: any FeatureContext
    let runner: ProcessRunner

    func register() {
        let commands = context.commands
        commands.register(Self.descriptors[0]) { try await openApp($0) }
        commands.register(Self.descriptors[1]) { try openURL($0) }
        commands.register(Self.descriptors[2]) { try await run(.shell(script: $0.string("script")), $0) }
        commands.register(Self.descriptors[3]) { try await run(.appleScript(source: $0.string("source")), $0) }
        commands.register(Self.descriptors[4]) { try await run(.shortcut(name: $0.string("name")), $0) }
        commands.register(Self.descriptors[5]) { try sendKeys($0) }
    }

    private func openApp(_ invocation: CommandInvocation) async throws {
        let target = try AppTarget(invocation.string("app"))
        try await AppLauncher.open(target)
    }

    private func openURL(_ invocation: CommandInvocation) throws {
        guard let url = try URLTarget.resolve(invocation.string("url")) else {
            throw CommandError.invalidArgument(key: "url", reason: "无法识别的地址")
        }
        NSWorkspace.shared.open(url)
    }

    private func run(_ job: ProcessJob, _ invocation: CommandInvocation) async throws {
        let result = try await runner.run(job)
        if result.exitCode != 0 {
            throw CommandError.failed("退出码 \(result.exitCode)：\(result.summary)")
        }
        if invocation.bool("showOutput", default: false), !result.summary.isEmpty {
            context.overlay.showHUD(result.summary, symbol: "terminal")
        }
    }

    private func sendKeys(_ invocation: CommandInvocation) throws {
        let raw = try invocation.string("keys")
        guard let chord = KeyChord(string: raw) else {
            throw CommandError.invalidArgument(key: "keys", reason: "无法解析按键 \(raw)")
        }
        context.input.poster.post(.keyStroke(chord))
    }
}
