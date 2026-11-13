import MAIOKit
import MAIOUI
import SwiftUI

/// Super Caps（全局 Caps 分层）：总开关、状态、层里的映射（每个键发出一个键 / 组合键，或执行一个 MAIO 命令）。
struct CapsLayerPage: View {
    let context: any FeatureContext
    let controller: RemapController?
    @State private var value: KeysSettings
    /// 能绑定的 MAIO 命令（不需要填参数的）
    private let commands: [AvailableCommand]

    init(context: any FeatureContext, controller: RemapController?) {
        self.context = context
        self.controller = controller
        _value = State(initialValue: context.settings.load(KeysSettings.self))
        commands = context.commands.availableCommands().filter(\.runsWithoutArguments)
    }

    var body: some View {
        Group {
            PageIntro(
                symbol: "capslock",
                title: "Super Caps",
                text: "把很少用的 Caps Lock 变成功能键：按住它，键盘上的键临时变成第二套功能，手不用离开主键区就能移动光标、翻页、执行命令。",
            )
            Section {
                Toggle("开启 Super Caps", isOn: $value.capsLayerEnabled)
                if let controller, value.capsLayerEnabled {
                    LabeledContent("状态") { statusBadge(controller.capsStatus) }
                }
            } footer: {
                NoteLines(
                    "对所有键盘生效。",
                    "开启后 Caps Lock 不再切换大小写、不亮灯，单独按下没有任何反应。",
                    "按住 Caps 再按其他键，执行下方「层里的键」设置的动作；没设置的键照常输出。",
                    "可以同时按住 ⇧ ⌃ ⌥ ⌘，它们会叠加到输出上：例如 Caps + ⇧ + S 等于 ⇧↓（向下选择）。",
                )
            }
            Section {
                ForEach(value.layer.indices, id: \.self) { index in
                    LayerEntryRow(
                        entry: entryBinding(index), commands: commands, input: context.input,
                        isDuplicate: isDuplicate(index),
                    ) { remove(at: index) }
                }
                HStack {
                    Text("添加：")
                    ShortcutRecorder(chord: nil, input: context.input) { add(KeyChord(keyCode: $0.keyCode, modifiers: [])) }
                    Text("按下层里的键").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("还原为默认层") { value.layer = LayerEntry.defaults }
                        .disabled(value.layer == LayerEntry.defaults)
                }
            } header: {
                Text("层里的键")
            } footer: {
                NoteLines(
                    "左侧是按住 Caps 时要按的键，点一下可以换成别的键。",
                    "右侧是要发出的按键或组合键，点一下重新录制，也可以改成执行一个 MAIO 命令。",
                    "同一个键只能设置一次，重复的行不生效。",
                )
            }
        }
        .onChange(of: value) { _, newValue in context.settings.save(newValue) }
    }

    /// 删除一行后 SwiftUI 可能还会用旧的位置读一次，越界时给个占位值，不崩溃
    private func entryBinding(_ index: Int) -> Binding<LayerEntry> {
        Binding(
            get: {
                value.layer.indices.contains(index)
                    ? value.layer[index] : LayerEntry(
                        key: KeyChord(keyCode: 0, modifiers: []),
                        action: .keys(KeyChord(keyCode: 0, modifiers: [])),
                    )
            },
            set: { newValue in
                if value.layer.indices.contains(index) {
                    value.layer[index] = newValue
                }
            },
        )
    }

    private func isDuplicate(_ index: Int) -> Bool {
        guard value.layer.indices.contains(index) else { return false }
        let key = value.layer[index].key.keyCode
        return value.layer.prefix(index).contains { $0.key.keyCode == key }
    }

    private func add(_ key: KeyChord) {
        // 已经有这个键时不重复添加
        guard !value.layer.contains(where: { $0.key.keyCode == key.keyCode }) else { return }
        value.layer.append(LayerEntry(key: key, action: .keys(key)))
    }

    private func remove(at index: Int) {
        guard value.layer.indices.contains(index) else { return }
        value.layer.remove(at: index)
    }

    @ViewBuilder private func statusBadge(_ status: RemapController.CapsStatus) -> some View {
        switch status {
        case .off: StatusBadge("已关闭", tone: .neutral)
        case .on: StatusBadge("工作中", tone: .positive)
        case .noInputMonitoring: StatusBadge("缺少输入监控权限，Caps 已恢复原样", tone: .warning)
        case let .failed(message): StatusBadge(message, tone: .negative)
        }
    }
}

/// 层里的一行：Caps + 键 → 按键 / 命令
private struct LayerEntryRow: View {
    @Binding var entry: LayerEntry
    let commands: [AvailableCommand]
    let input: any InputService
    let isDuplicate: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Text("Caps +")
            ShortcutRecorder(chord: entry.key, input: input) { entry.key = KeyChord(keyCode: $0.keyCode, modifiers: []) }
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            ActionEditor(action: $entry.action, commands: commands, input: input, fallbackChord: entry.key)
            if isDuplicate {
                Text("重复，不生效").font(.caption).foregroundStyle(.orange)
            }
            Spacer()
            DeleteButton(action: onDelete)
        }
    }
}
