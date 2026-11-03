import MAIOKit

/// 命令处理：只做参数解析与调度，业务逻辑放在 Domain/。
@MainActor
struct __NAME__Commands {
    static let hello: CommandID = "__ID__.hello"

    static let descriptors: [CommandDescriptor] = [
        CommandDescriptor(id: hello, title: "__NAME__：示例命令"),
    ]

    let context: any FeatureContext

    func register() {
        context.commands.register(Self.descriptors[0]) { _ in
            context.overlay.showHUD("Hello from __NAME__")
        }
    }
}
