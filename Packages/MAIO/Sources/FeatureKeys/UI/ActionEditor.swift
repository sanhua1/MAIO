import MAIOKit
import MAIOUI
import SwiftUI

/// 改键的输出：组合键（录制）/ 单键（从列表选，全局改键里在 HID 层做）/ MAIO 命令。Caps 层、全局改键、鼠标按钮共用。
struct ActionEditor: View {
    enum Kind: String, CaseIterable {
        case keys = "组合键"
        case singleKey = "单键"
        case command = "命令"
    }

    @Binding var action: LayerAction
    let commands: [AvailableCommand]
    let input: any InputService
    /// 换成"组合键"时的初始值
    let fallbackChord: KeyChord
    /// 能不能选"单键"（只有全局改键用得上）
    var kinds: [Kind] = [.keys, .command]

    var body: some View {
        Picker("类型", selection: kindBinding) {
            ForEach(kinds, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
        switch action {
        case let .keys(chord):
            ShortcutRecorder(chord: chord, input: input) { action = .keys($0) }
        case let .hidKey(name):
            HIDKeyPicker(selection: Binding(get: { name }, set: { action = .hidKey($0) }))
        case let .command(id):
            Picker("命令", selection: Binding(get: { id }, set: { action = .command($0) })) {
                if !commands.contains(where: { $0.id == id }) {
                    Text("（未启用）\(id.rawValue)").tag(id)
                }
                ForEach(commands, id: \.id) { command in
                    Text("\(command.featureName) › \(command.descriptor.title)").tag(command.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 260)
        }
    }

    private var kindBinding: Binding<Kind> {
        Binding(
            get: {
                switch action {
                case .keys: .keys
                case .hidKey: .singleKey
                case .command: .command
                }
            },
            set: { kind in
                switch kind {
                case .keys: action = .keys(fallbackChord)
                case .singleKey: action = .hidKey(HIDKey.with(keyCode: fallbackChord.keyCode)?.name ?? "escape")
                case .command:
                    if let first = commands.first {
                        action = .command(first.id)
                    }
                }
            },
        )
    }
}

/// 从键表里选一个键（包括没有虚拟键码的 F21～F24、左右修饰键、Fn）
struct HIDKeyPicker: View {
    @Binding var selection: String

    var body: some View {
        Picker("键", selection: $selection) {
            ForEach(HIDKey.all, id: \.name) { Text($0.symbol).tag($0.name) }
        }
        .labelsHidden()
        .frame(maxWidth: 140)
    }
}

struct DeleteButton: View {
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) { Image(systemName: "minus.circle") }
            .buttonStyle(.borderless)
            .help("删除")
    }
}
