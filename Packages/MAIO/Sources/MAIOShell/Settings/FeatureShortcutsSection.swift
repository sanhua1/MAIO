import MAIOCore
import MAIOKit
import MAIOUI
import SwiftUI

/// 功能页里的"快捷键"区：直接显示并录制这个功能的快捷键。
/// 和「MAIO 快捷键」页读写的是同一份绑定（`BindingStore`），一边改了另一边立刻同步。
/// 不需要参数的命令每个一行，点键帽直接录；需要参数的（例如"打开 App"）把已有的绑定逐条列出，
/// 双击或右键编辑，"添加快捷键…"在这里直接新建。
struct FeatureShortcutsSection: View {
    let controller: MAIOAppController
    let manifest: FeatureManifest
    @State private var editing: CommandBinding?
    @State private var isNew = false

    private var store: BindingStore {
        controller.runtime.bindings
    }

    private var simpleCommands: [CommandDescriptor] {
        manifest.commands.filter { command in command.parameters.allSatisfy { !$0.isRequired } }
    }

    private var parameterizedCommands: [CommandDescriptor] {
        manifest.commands.filter { command in command.parameters.contains { $0.isRequired } }
    }

    /// 不在"一命令一行"里显示的绑定：需要参数的命令，以及带了参数的简单命令。按命令在清单里的顺序排。
    private var parameterizedBindings: [CommandBinding] {
        let order = manifest.commands.map(\.id)
        let simple = Set(simpleCommands.map(\.id))
        return store.bindings
            .filter { order.contains($0.command) && (!simple.contains($0.command) || !$0.arguments.isEmpty) }
            .enumerated()
            .sorted { lhs, rhs in
                let left = order.firstIndex(of: lhs.element.command) ?? 0
                let right = order.firstIndex(of: rhs.element.command) ?? 0
                return (left, lhs.offset) < (right, rhs.offset)
            }
            .map(\.element)
    }

    var body: some View {
        Section {
            ForEach(simpleCommands) { command in
                row(command)
            }
            ForEach(parameterizedBindings) { binding in
                BindingRow(controller: controller, binding: binding)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { edit(binding) }
                    .contextMenu { menu(for: binding) }
            }
            if let first = parameterizedCommands.first {
                Button("添加快捷键…", systemImage: "plus") { add(first.id) }
            }
        } header: {
            Text("快捷键")
        } footer: {
            Text(footer).font(.caption).foregroundStyle(.secondary)
        }
        .sheet(item: $editing) { binding in
            BindingEditor(controller: controller, original: binding, isNew: isNew) { editing = nil }
        }
    }

    private var footer: String {
        if controller.runtime.input.status != .running {
            return "尚未授予“辅助功能”权限，不能录制，快捷键也暂不生效。"
        }
        let base = "点按键帽后按下新的组合键；录制时按 ⌫ 删除这个快捷键，按 Esc 取消。右键可以设置生效范围。"
        let extra = parameterizedCommands.isEmpty ? "" : "带参数的快捷键双击或右键编辑。"
        return base + extra + "和「MAIO 快捷键」页是同一份设置。"
    }

    private func row(_ command: CommandDescriptor) -> some View {
        let bindings = store.bindings.filter { $0.command == command.id && $0.arguments.isEmpty }
        return LabeledContent {
            HStack(spacing: 6) {
                ForEach(bindings) { binding in
                    ShortcutRecorderButton(controller: controller, chord: chord(of: binding)) { recorded in
                        update(binding, to: recorded)
                    }
                    .opacity(binding.isEnabled ? 1 : 0.5)
                    .contextMenu { menu(for: binding) }
                    BindingStatus(controller: controller, binding: binding)
                }
                if bindings.isEmpty {
                    ShortcutRecorderButton(controller: controller, chord: nil) { recorded in
                        guard let recorded else { return }
                        store.upsert(CommandBinding(id: BindingStore.makeID(), trigger: .hotkey(recorded), command: command.id))
                    }
                }
            }
        } label: {
            Text(command.title)
            if let summary = command.summary {
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func edit(_ binding: CommandBinding) {
        isNew = false
        editing = binding
    }

    private func add(_ command: CommandID) {
        isNew = true
        editing = CommandBinding(
            id: BindingStore.makeID(),
            trigger: .hotkey(KeyChord(keyCode: 0, modifiers: [.function, .shift])),
            command: command,
        )
    }

    @ViewBuilder
    private func menu(for binding: CommandBinding) -> some View {
        Button("编辑（生效范围等）…") { edit(binding) }
        Button(binding.isEnabled ? "停用" : "启用") {
            var copy = binding
            copy.isEnabled.toggle()
            store.upsert(copy)
        }
        Button("删除", role: .destructive) { store.remove(id: binding.id) }
    }

    private func chord(of binding: CommandBinding) -> KeyChord? {
        if case let .hotkey(chord) = binding.trigger {
            return chord
        }
        return nil
    }

    /// recorded 为 nil 表示删除
    private func update(_ binding: CommandBinding, to recorded: KeyChord?) {
        guard let recorded else {
            store.remove(id: binding.id)
            return
        }
        var copy = binding
        copy.trigger = .hotkey(recorded)
        store.upsert(copy)
    }
}

/// 键帽样式的录制按钮：点一下开始录，按下组合键即保存；⌫ 删除（回调 nil），Esc 取消。
struct ShortcutRecorderButton: View {
    let controller: MAIOAppController
    let chord: KeyChord?
    let onChange: (KeyChord?) -> Void
    @State private var isRecording = false

    var body: some View {
        Button(action: toggle) {
            Group {
                if isRecording {
                    Text("按下快捷键…").foregroundStyle(.secondary)
                } else if let chord {
                    Text(chord.displayString)
                } else {
                    Text("录制快捷键").foregroundStyle(.secondary)
                }
            }
            .font(.system(.callout, design: .rounded).weight(.medium))
            .frame(minWidth: 64)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: .rect(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isRecording ? Color.accentColor : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .disabled(controller.runtime.input.status != .running)
        .help("点按后按下新的组合键")
        .onDisappear(perform: stop)
    }

    private func toggle() {
        guard !isRecording else {
            stop()
            return
        }
        isRecording = true
        controller.runtime.input.beginRecording { recorded in
            stop()
            guard recorded.modifiers.isEmpty else {
                onChange(recorded)
                return
            }
            switch recorded.keyCode {
            case KeyCodes.escape: break
            case KeyCodes.delete: if chord != nil {
                    onChange(nil)
                }
            default: onChange(recorded)
            }
        }
    }

    private func stop() {
        guard isRecording else { return }
        isRecording = false
        controller.runtime.input.endRecording()
    }
}
