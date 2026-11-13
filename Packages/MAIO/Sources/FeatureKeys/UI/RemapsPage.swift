import MAIOKit
import MAIOUI
import SwiftUI

/// 其他改键（全局）：键 → 单键 / 组合键 / 命令；鼠标中键、侧键 → 组合键 / 命令。
struct RemapsPage: View {
    let context: any FeatureContext
    @State private var value: KeysSettings
    private let commands: [AvailableCommand]

    init(context: any FeatureContext) {
        self.context = context
        _value = State(initialValue: context.settings.load(KeysSettings.self))
        commands = context.commands.availableCommands().filter(\.runsWithoutArguments)
    }

    var body: some View {
        Group {
            PageIntro(
                symbol: "arrow.left.arrow.right",
                title: "其他改键",
                text: "把某个键或鼠标按钮改成别的键、组合键，或者直接执行 MAIO 命令。例如 Home → 行首（⌘←）、鼠标侧键 → 关闭标签页（⌘W）。",
            )
            Section {
                ForEach(value.remaps.indices, id: \.self) { index in
                    KeyRemapRow(
                        remap: binding(\.remaps, index, placeholder: Self.placeholder),
                        commands: commands,
                        input: context.input,
                    ) {
                        remove(\.remaps, at: index)
                    }
                }
                Button("添加改键") { value.remaps.append(Self.placeholder) }
            } header: {
                Text("键盘")
            } footer: {
                NoteLines(
                    "对所有键盘生效；按住 Caps 时以 Super Caps 的设置为准。",
                    "「单键」：在系统底层替换，密码框里也有效；可以选 Fn、左右修饰键、F13～F24。",
                    "「组合键」「命令」：由 MAIO 拦截后改发，按住时组合键会连发。",
                    "同时按下的 ⇧ ⌃ ⌥ ⌘ 会叠加上去：例如 Home → ⌘←，那么 ⇧Home 就是 ⇧⌘←（选中到行首）。",
                )
            }
            Section {
                ForEach(value.mouseRemaps.indices, id: \.self) { index in
                    MouseRemapRow(
                        remap: binding(\.mouseRemaps, index, placeholder: Self.mousePlaceholder),
                        commands: commands, input: context.input,
                    ) { remove(\.mouseRemaps, at: index) }
                }
                Button("添加鼠标按键") { value.mouseRemaps.append(nextMouseRemap()) }
            } header: {
                Text("鼠标")
            } footer: {
                NoteLines(
                    "支持鼠标中键和侧键。",
                    "设置后按钮原来的功能（例如浏览器的后退 / 前进）会被替换。",
                )
            }
        }
        .onChange(of: value) { _, newValue in context.settings.save(newValue) }
    }

    private static let placeholder = KeyRemap(from: "home", action: .keys(KeyChord(keyCode: 123, modifiers: .command)))
    private static let mousePlaceholder = MouseRemap(button: 3, action: .keys(KeyChord(keyCode: 13, modifiers: .command)))

    private func nextMouseRemap() -> MouseRemap {
        let used = Set(value.mouseRemaps.map(\.button))
        let button = [3, 4, 2, 5, 6, 7].first { !used.contains($0) } ?? 3
        return MouseRemap(button: button, action: Self.mousePlaceholder.action)
    }

    /// 删除一行后 SwiftUI 可能还会用旧的位置读一次，越界时给个占位值，不崩溃
    private func binding<Item>(_ list: WritableKeyPath<KeysSettings, [Item]>, _ index: Int, placeholder: Item) -> Binding<Item> {
        Binding(
            get: { value[keyPath: list].indices.contains(index) ? value[keyPath: list][index] : placeholder },
            set: { newValue in
                if value[keyPath: list].indices.contains(index) {
                    value[keyPath: list][index] = newValue
                }
            },
        )
    }

    private func remove(_ list: WritableKeyPath<KeysSettings, [some Any]>, at index: Int) {
        if value[keyPath: list].indices.contains(index) {
            value[keyPath: list].remove(at: index)
        }
    }
}

private struct KeyRemapRow: View {
    @Binding var remap: KeyRemap
    let commands: [AvailableCommand]
    let input: any InputService
    let onDelete: () -> Void

    private var from: HIDKey? {
        HIDKey.named(remap.from)
    }

    var body: some View {
        HStack {
            Toggle("启用", isOn: $remap.isEnabled).labelsHidden()
            HIDKeyPicker(selection: $remap.from)
            ShortcutRecorder(chord: nil, input: input) { chord in
                if let key = HIDKey.with(keyCode: chord.keyCode) {
                    remap.from = key.name
                }
            }
            .help("按一下要改的键，代替从列表里找")
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            ActionEditor(
                action: $remap.action, commands: commands, input: input,
                fallbackChord: KeyChord(keyCode: from?.keyCode ?? 53, modifiers: []), kinds: ActionEditor.Kind.allCases,
            )
            if remap.action.isTapAction, from?.keyCode == nil {
                Text("这个键只能换成单键").font(.caption).foregroundStyle(.orange)
            }
            Spacer()
            DeleteButton(action: onDelete)
        }
    }
}

private struct MouseRemapRow: View {
    @Binding var remap: MouseRemap
    let commands: [AvailableCommand]
    let input: any InputService
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Toggle("启用", isOn: $remap.isEnabled).labelsHidden()
            Picker("按钮", selection: $remap.button) {
                ForEach(2 ... 7, id: \.self) { Text(MouseRemap.title(for: $0)).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            ActionEditor(
                action: $remap.action,
                commands: commands,
                input: input,
                fallbackChord: KeyChord(keyCode: 13, modifiers: .command),
            )
            Spacer()
            DeleteButton(action: onDelete)
        }
    }
}
