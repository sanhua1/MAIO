import MAIOKit
import MAIOUI
import SwiftUI

/// Caps 分层（全局）：总开关、状态、层里的映射（每个键发出一个键 / 组合键，或执行一个 MAIO 命令）。
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
            Section {
                Toggle("打开 Caps 分层", isOn: $value.capsLayerEnabled)
                if let controller, value.capsLayerEnabled {
                    LabeledContent("状态") { statusBadge(controller.capsStatus) }
                }
            } footer: {
                Text("对所有键盘生效。打开后 Caps 原本的功能完全没有：不切换大写、不亮灯，单按什么都不发生；按住 Caps 时用下面这一层。层里按 ⇧⌃⌥⌘ 会叠加到输出上（Caps+⇧+S = ⇧↓）。没设置的键照常输出。")
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
                Text("点左边的键可以换成别的键；点右边录制要发出的键或组合键，或者改成执行 MAIO 命令。")
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
