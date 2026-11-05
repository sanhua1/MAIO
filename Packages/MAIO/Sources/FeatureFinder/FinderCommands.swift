import Foundation
import MAIOKit

/// 命令处理：只做参数解析与调度。这些命令也可以在快捷键页绑定到别的按键。
@MainActor
struct FinderCommands {
    static let newTextFile: CommandID = "finder.newTextFile"
    static let openTerminal: CommandID = "finder.openTerminal"
    static let restartFinder: CommandID = "finder.restartFinder"
    static let contextMenu: CommandID = "finder.contextMenu"

    static let descriptors: [CommandDescriptor] = [
        CommandDescriptor(id: newTextFile, title: "Finder：在当前位置新建文本文件"),
        CommandDescriptor(id: openTerminal, title: "Finder：在终端中打开当前位置"),
        CommandDescriptor(id: restartFinder, title: "Finder：重启 Finder"),
        CommandDescriptor(
            id: contextMenu, title: "Finder：执行右键菜单动作",
            summary: "Finder 右键菜单扩展通过 maio:// 调用，一般不需要手动绑定",
            parameters: [
                ParameterSpec(key: "action", title: "动作", kind: .text),
                ParameterSpec(key: "target", title: "所在文件夹", kind: .text, isRequired: false),
                ParameterSpec(key: "items", title: "选中项（每行一个路径）", kind: .multilineText, isRequired: false),
            ],
        ),
    ]

    let context: any FeatureContext
    let enhancer: FinderEnhancer

    func register() {
        context.commands.register(descriptor(Self.newTextFile)) { [enhancer] _ in await enhancer.newTextFile() }
        context.commands.register(descriptor(Self.openTerminal)) { [enhancer] _ in await enhancer.openTerminal() }
        context.commands.register(descriptor(Self.restartFinder)) { _ in FinderPreferences.restartFinder() }
        context.commands.register(descriptor(Self.contextMenu), handler: { [enhancer] invocation in
            let target = invocation.optionalString("target").map { URL(filePath: $0) }
            let items = (invocation.optionalString("items") ?? "").split(separator: "\n").map { URL(filePath: String($0)) }
            try await enhancer.performContextMenu(action: invocation.string("action"), target: target, items: items)
        })
    }

    private func descriptor(_ id: CommandID) -> CommandDescriptor {
        Self.descriptors.first { $0.id == id } ?? CommandDescriptor(id: id, title: id.rawValue)
    }
}
