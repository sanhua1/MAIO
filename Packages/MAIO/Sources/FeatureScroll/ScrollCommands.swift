import MAIOKit

/// 可绑定到快捷键的命令：临时开关反转 / 平滑。
@MainActor
struct ScrollCommands {
    static let toggleReverse: CommandID = "scroll.toggleReverse"
    static let toggleSmooth: CommandID = "scroll.toggleSmooth"

    static let descriptors: [CommandDescriptor] = [
        CommandDescriptor(id: toggleReverse, title: "开关鼠标滚动反转"),
        CommandDescriptor(id: toggleSmooth, title: "开关平滑滚动"),
    ]

    let context: any FeatureContext

    func register() {
        context.commands.register(Self.descriptors[0], handler: { _ in
            var settings = context.settings.load(ScrollSettings.self)
            let enabled = !(settings.reverseVertical || settings.reverseHorizontal)
            settings.reverseVertical = enabled
            settings.reverseHorizontal = enabled
            context.settings.save(settings)
            context.overlay.showHUD(enabled ? "鼠标滚动反转：开" : "鼠标滚动反转：关", symbol: "arrow.up.arrow.down")
        })
        context.commands.register(Self.descriptors[1], handler: { _ in
            var settings = context.settings.load(ScrollSettings.self)
            settings.smoothEnabled.toggle()
            context.settings.save(settings)
            context.overlay.showHUD(settings.smoothEnabled ? "平滑滚动：开" : "平滑滚动：关", symbol: "scroll")
        })
    }
}
