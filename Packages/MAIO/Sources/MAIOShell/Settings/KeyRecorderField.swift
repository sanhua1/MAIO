import MAIOKit
import MAIOUI
import SwiftUI

/// 快捷键录制：通过输入引擎捕获按键，所以 Fn 组合、系统快捷键都能录到。
/// 输入引擎未运行（没有权限）时，可以直接输入文本，例如 "fn+a"。
struct KeyRecorderField: View {
    let controller: MAIOAppController
    @SwiftUI.Binding var chord: KeyChord
    @State private var isRecording = false
    @State private var text = ""

    var body: some View {
        HStack {
            if isRecording {
                Text("请按下快捷键…（Esc 取消）")
                    .foregroundStyle(.secondary)

            } else {
                KeyChordLabel(chord)
            }
            Button(isRecording ? "取消" : "录制") { isRecording ? stop() : start() }
                .disabled(controller.runtime.input.status != .running)
            // 标题留空：在 Form 里 TextField 的标题会变成左侧标签，把这一行挤乱
            TextField("", text: $text, prompt: Text("或输入 fn+a"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
                .onSubmit(applyText)
        }
        .onDisappear(perform: stop)
        .onAppear { text = chord.string }
    }

    private func start() {
        isRecording = true
        controller.runtime.input.beginRecording { recorded in
            if recorded.keyCode != KeyCodes.escape || !recorded.modifiers.isEmpty {
                chord = recorded
                text = recorded.string
            }
            stop()
        }
    }

    private func stop() {
        guard isRecording else { return }
        isRecording = false
        controller.runtime.input.endRecording()
    }

    private func applyText() {
        if let parsed = KeyChord(string: text) {
            chord = parsed
            text = parsed.string
        } else {
            text = chord.string
        }
    }
}
