import MAIOKit

/// 命令处理：只做参数解析与调度，业务逻辑放在 Domain/。
@MainActor
struct ScreenshotCommands {
    static let capture: CommandID = "screenshot.capture"
    static let fullScreen: CommandID = "screenshot.fullScreen"
    static let window: CommandID = "screenshot.window"
    static let ocr: CommandID = "screenshot.ocr"
    static let translate: CommandID = "screenshot.translate"
    static let scrolling: CommandID = "screenshot.scrolling"
    static let pinClipboard: CommandID = "screenshot.pinClipboard"
    static let pinLast: CommandID = "screenshot.pinLast"
    static let history: CommandID = "screenshot.history"
    static let closeAllPins: CommandID = "screenshot.closeAllPins"

    static let descriptors: [CommandDescriptor] = [
        CommandDescriptor(
            id: capture, title: "截图",
            summary: "冻结屏幕后框选区域，自动识别窗口（按住 ⌘ 识别控件），可以标注。⏎ 复制，⌘S 保存，⌘P 贴图，⌘O 识别文字，⌘T 翻译，⌘L 长截图。默认 ⌥F1",
        ),
        CommandDescriptor(id: fullScreen, title: "全屏截图", summary: "截取鼠标所在的屏幕，直接复制并写入截图历史"),
        CommandDescriptor(
            id: ocr, title: "截图识别文字",
            summary: "框选区域后按 ⏎ 识别其中的文字（系统 Vision，离线），在结果窗口里编辑、复制、翻译",
        ),
        CommandDescriptor(id: translate, title: "截图翻译", summary: "框选区域后按 ⏎ 识别文字并直接打开翻译窗口"),
        CommandDescriptor(
            id: scrolling, title: "长截图",
            summary: "框选区域后按 ⏎ 开始：自己用滚轮往下滚，自动拼接，右侧显示长条预览；Esc / ⏎ / 完成按钮结束，然后进入标注",
        ),
        CommandDescriptor(id: window, title: "窗口截图", summary: "截取最前面的窗口（保留圆角，不带阴影），直接复制并写入截图历史"),
        CommandDescriptor(
            id: pinClipboard, title: "贴剪贴板内容",
            summary: "把剪贴板里的图片（文字会渲染成图片）钉在屏幕上，并写入截图历史。默认 ⌥F2",
        ),
        CommandDescriptor(id: pinLast, title: "重新贴最近一张截图", summary: "把截图历史里最新的一张钉在屏幕上（同时复制）"),
        CommandDescriptor(id: history, title: "截图历史", summary: "打开截图历史：重新贴图、复制、编辑标注、删除"),
        CommandDescriptor(id: closeAllPins, title: "关闭全部贴图", summary: "关闭屏幕上所有贴图（可以从截图历史找回）"),
        ScreenshotPinContract.descriptor,
    ]

    let context: any FeatureContext
    let controller: ScreenshotController

    func register() {
        let handlers: [CommandID: @MainActor () async -> Void] = [
            Self.capture: { await controller.capture() },
            Self.ocr: { await controller.capture(primaryAction: .ocr) },
            Self.translate: { await controller.capture(primaryAction: .translate) },
            Self.scrolling: { await controller.capture(primaryAction: .scrolling) },
            Self.fullScreen: { await controller.captureFullScreen() },
            Self.window: { await controller.captureFrontWindow() },
            Self.pinClipboard: { await controller.pinClipboard() },
            Self.pinLast: { await controller.pinLast() },
            Self.history: { controller.showHistory() },
            Self.closeAllPins: { controller.pins.closeAll() },
        ]
        context.commands.register(ScreenshotPinContract.self) { input in
            try await controller.pin(input)
            return NoOutput()
        }
        for descriptor in Self.descriptors {
            guard let handler = handlers[descriptor.id] else { continue }
            context.commands.register(descriptor) { _ in await handler() }
        }
    }
}
