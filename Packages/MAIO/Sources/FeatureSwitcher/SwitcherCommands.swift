import MAIOKit

@MainActor
struct SwitcherCommands {
    static let show: CommandID = "switcher.show"
    static let showReverse: CommandID = "switcher.showReverse"

    static let descriptors: [CommandDescriptor] = [
        CommandDescriptor(
            id: show, title: "窗口切换",
            summary: "按住修饰键再按主键切换，松开修饰键即切换到选中的窗口",
        ),
        CommandDescriptor(id: showReverse, title: "窗口切换（反向）", summary: "从最后一项开始，通常绑定到带 ⇧ 的版本"),
    ]

    let controller: SwitcherController

    func register(on registrar: any CommandRegistrar) {
        registrar.register(Self.descriptors[0], handler: { invocation in
            controller.start(trigger: invocation.triggerChord, reverse: false)
        })
        registrar.register(Self.descriptors[1], handler: { invocation in
            controller.start(trigger: invocation.triggerChord, reverse: true)
        })
    }
}

private extension CommandInvocation {
    var triggerChord: KeyChord? {
        if case let .hotkey(_, chord) = source {
            return chord
        }
        return nil
    }
}
