import MAIOKit

@MainActor
struct ClipboardCommands {
    static let show: CommandID = "clipboard.show"

    static let descriptors: [CommandDescriptor] = [
        CommandDescriptor(
            id: show, title: "剪贴板历史",
            summary: "在光标处弹出剪贴板历史，回车粘贴。默认 ⌃V；不想在某些 App 里生效时，编辑这条绑定的生效范围",
        ),
    ]

    let context: any FeatureContext
    let panel: ClipboardPanelController

    func register() {
        context.commands.register(Self.descriptors[0]) { _ in await panel.toggle() }
    }
}
