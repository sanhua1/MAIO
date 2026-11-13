import MAIOCore
import MAIOKit
import MAIOUI
import SwiftUI

/// 「MAIO 快捷键」页：所有绑定的总表。按类别分标签，标签内再按功能分组；搜索、启停、编辑、冲突提示。
/// 功能自己的快捷键也可以在各功能页里直接设置（`FeatureShortcutsSection`），两边是同一份数据。
struct ShortcutsPane: View {
    let controller: MAIOAppController
    @State private var search = ""
    @State private var category: ShortcutCategory = .all
    @State private var editing: CommandBinding?
    @State private var isNew = false

    private var store: BindingStore {
        controller.runtime.bindings
    }

    var body: some View {
        VStack(spacing: 0) {
            if controller.runtime.input.status != .running {
                permissionBanner
            }
            Picker("类别", selection: $category) {
                ForEach(ShortcutCategory.allCases) { item in
                    Text("\(item.rawValue) \(count(of: item))").tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            List {
                ForEach(ShortcutGroup.make(filtered, catalog: controller.commandCatalog)) { group in
                    Section {
                        ForEach(group.bindings) { binding in
                            BindingRow(controller: controller, binding: binding)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { edit(binding) }
                                .contextMenu {
                                    Button("编辑…") { edit(binding) }
                                    Button("删除", role: .destructive) { store.remove(id: binding.id) }
                                }
                        }
                    } header: {
                        ShortcutGroupHeader(group: group)
                    }
                }
            }
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView("没有快捷键", systemImage: "keyboard", description: Text("点击右上角的 + 添加"))
                }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "搜索快捷键或命令")
        .navigationTitle("MAIO 快捷键")
        .toolbar {
            Button("添加", systemImage: "plus") { add() }
        }
        .sheet(item: $editing) { binding in
            BindingEditor(controller: controller, original: binding, isNew: isNew) { editing = nil }
        }
    }

    private var filtered: [CommandBinding] {
        store.bindings.filter { binding in
            let presentation = BindingPresentation(binding: binding, catalog: controller.commandCatalog)
            guard category.contains(presentation.category) else { return false }
            guard !search.isEmpty else { return true }
            let haystack = [
                binding.trigger.displayString, binding.command.rawValue, presentation.title, presentation.descriptor?.title ?? "",
            ]
            return haystack.contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }

    private func count(of category: ShortcutCategory) -> Int {
        store.bindings.count { binding in
            category.contains(BindingPresentation(binding: binding, catalog: controller.commandCatalog).category)
        }
    }

    private var permissionBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("尚未授予“辅助功能”权限，快捷键暂不生效。")
            Spacer()
            Button("前往授权") { controller.showSettings(pane: .general) }
        }
        .padding(10)
        .background(.orange.opacity(0.1))
    }

    private func add() {
        isNew = true
        editing = CommandBinding(
            id: BindingStore.makeID(),
            trigger: .hotkey(KeyChord(keyCode: 0, modifiers: [.function, .shift])),
            command: "system.openApp",
        )
    }

    private func edit(_ binding: CommandBinding) {
        isNew = false
        editing = binding
    }
}

/// 一条绑定的行：开关、键帽、图标、名称、说明、状态（「MAIO 快捷键」页和功能页共用）
struct BindingRow: View {
    let controller: MAIOAppController
    let binding: CommandBinding
    /// 开关用自己的状态，不用 `Binding(get:set:)` 闭包：2026-11-12 在这个闭包里崩过一次
    /// （设置窗口重新排版时调用了已经失效的闭包，EXC_BAD_ACCESS，见 PROGRESS"已知问题"）
    @State private var isOn: Bool

    init(controller: MAIOAppController, binding: CommandBinding) {
        self.controller = controller
        self.binding = binding
        _isOn = State(initialValue: binding.isEnabled)
    }

    var body: some View {
        let presentation = BindingPresentation(binding: binding, catalog: controller.commandCatalog)
        HStack(spacing: 12) {
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
            KeyChordLabel(text: binding.trigger.displayString).frame(minWidth: 70, alignment: .leading)
            presentation.icon
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.title)
                Text(detail(presentation)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            BindingStatus(controller: controller, binding: binding)
        }
        .opacity(binding.isEnabled ? 1 : 0.5)
        .onChange(of: isOn) { _, value in
            guard value != binding.isEnabled else { return }
            var copy = binding
            copy.isEnabled = value
            controller.runtime.bindings.upsert(copy)
        }
        // 别处（功能页、编辑框）改了启停时同步过来
        .onChange(of: binding.isEnabled) { _, value in isOn = value }
    }

    /// 第二行：MAIO 功能（功能名已在分组标题里）有备注时显示命令名，否则显示命令说明；其他显示参数
    private func detail(_ presentation: BindingPresentation) -> String {
        if presentation.category == .features {
            if binding.title != nil {
                return presentation.descriptor?.title ?? binding.command.rawValue
            }
            return presentation.descriptor?.summary ?? ""
        }
        let arguments = binding.arguments.sorted { $0.key < $1.key }
            .compactMap { _, value -> String? in
                value.stringValue ?? value.boolValue.map { $0 ? "是" : "否" } ?? value.numberValue.map { "\($0)" }
            }
        return ([presentation.descriptor?.title ?? binding.command.rawValue] + arguments).joined(separator: "  ")
    }
}
