import CoreGraphics
import MAIOKit
import MAIOUI

/// 命令处理：只做参数解析与调度。
@MainActor
struct TranslateCommands {
    static let show: CommandID = "translate.show"
    static let selection: CommandID = "translate.selection"
    static let input: CommandID = "translate.input"

    static let descriptors: [CommandDescriptor] = [
        CommandDescriptor(
            id: show, title: "翻译",
            summary: "默认：有选中文字就翻译，否则打开输入框（行为可在翻译设置中修改）",
        ),
        CommandDescriptor(id: selection, title: "翻译选中的文字", summary: "没有选中文字时提示"),
        CommandDescriptor(id: input, title: "打开翻译输入框"),
        TranslateTextContract.descriptor,
    ]

    let context: any FeatureContext
    let window: TranslateWindowController

    func register() {
        let commands = context.commands
        commands.register(Self.descriptors[0]) { _ in await showByBehavior() }
        commands.register(Self.descriptors[1]) { _ in await translateSelection(fallbackToInput: false) }
        commands.register(Self.descriptors[2]) { _ in window.show(text: "") }
        commands.register(TranslateTextContract.self) { input in
            window.show(text: input.text)
            return NoOutput()
        }
    }

    private func showByBehavior() async {
        switch context.settings.load(TranslateSettings.self).hotkeyBehavior {
        case .smart: await translateSelection(fallbackToInput: true)
        case .selectionOnly: await translateSelection(fallbackToInput: false)
        case .inputOnly: window.show(text: "")
        }
    }

    private func translateSelection(fallbackToInput: Bool) async {
        // 焦点在翻译窗口里时，不去读其他 App 的选中文字，直接重新翻译输入框内容
        if window.isFocused {
            window.retranslate()
            return
        }
        // 先记下选中文字的位置（"所选文字旁边"用），再读文字
        let wantsRect = context.settings.load(TranslateSettings.self).selectionWindowPosition == .nearSelection
        let rect = wantsRect ? await TextCaretLocator.selectionRect() : nil
        let text = await SelectionReader(poster: context.input.poster).read()
        if let text {
            window.show(text: text, trigger: .selection(rect))
        } else if fallbackToInput {
            window.show(text: "")
        } else {
            context.overlay.showHUD("没有选中的文字", symbol: "character.cursor.ibeam")
        }
    }
}
