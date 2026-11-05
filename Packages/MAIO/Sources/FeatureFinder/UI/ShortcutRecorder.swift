import MAIOKit
import MAIOUI
import SwiftUI

/// 录制快捷键的按钮：点一下开始录，按下组合键即保存，Esc 取消。录制期间按键不会传给其他 App（键盘会话）。
struct ShortcutRecorder: View {
    let chord: KeyChord?
    let input: any InputService
    let onChange: (KeyChord) -> Void
    @State private var session: (any KeyboardSession)?
    @State private var held: KeyModifiers = []

    var body: some View {
        Button(action: toggle) {
            Text(label)
                .frame(minWidth: 70)
                .foregroundStyle(session == nil ? (chord == nil ? .secondary : .primary) : Color.accentColor)
        }
        .help(session == nil ? "点击后按下新的快捷键" : "按下组合键；Esc 取消")
        .onDisappear(perform: stop)
    }

    private var label: String {
        if session != nil {
            return held.isEmpty ? "按下快捷键…" : held.symbols + "…"
        }
        return chord?.displayString ?? "未设置"
    }

    private func toggle() {
        if session == nil {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        let session = input.beginKeyboardSession()
        self.session = session
        held = []
        Task { @MainActor in
            for await event in session.events {
                switch event.kind {
                case .flagsChanged:
                    held = event.modifiers.subtracting(.function)
                case .down where event.keyCode == FinderKeymap.Key.escape && event.modifiers.isEmpty:
                    stop()
                case .down where !KeyCodes.modifierKeys.contains(event.keyCode):
                    stop()
                    onChange(event.chord)
                default:
                    break
                }
            }
        }
    }

    private func stop() {
        session?.end()
        session = nil
        held = []
    }
}

/// 冲突提示列表（红色：不会生效；橙色：会覆盖别的；灰色：说明）
struct WarningList: View {
    let warnings: [ShortcutWarning]

    var body: some View {
        ForEach(warnings) { warning in
            Label(warning.text, systemImage: symbol(warning.level))
                .font(.caption)
                .foregroundStyle(color(warning.level))
        }
    }

    private func symbol(_ level: ShortcutWarning.Level) -> String {
        switch level {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        }
    }

    private func color(_ level: ShortcutWarning.Level) -> Color {
        switch level {
        case .info: .secondary
        case .warning: .orange
        case .error: .red
        }
    }
}
