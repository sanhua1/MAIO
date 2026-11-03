import MAIOCore
import MAIOKit
import MAIOUI
import SwiftUI

/// 所有绑定的总表：按类别分标签、搜索、启停、编辑、冲突提示。
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
                ForEach(filtered) { binding in
                    BindingRow(controller: controller, binding: binding)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { edit(binding) }
                        .contextMenu {
                            Button("编辑…") { edit(binding) }
                            Button("删除", role: .destructive) { store.remove(id: binding.id) }
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
        .navigationTitle("快捷键")
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
            Button("前往授权") { controller.showSettings(pane: .permissions) }
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

private struct BindingRow: View {
    let controller: MAIOAppController
    let binding: CommandBinding

    var body: some View {
        let presentation = BindingPresentation(binding: binding, catalog: controller.commandCatalog)
        HStack(spacing: 12) {
            Toggle("", isOn: enabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
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
    }

    /// 第二行：MAIO 功能显示"功能名 · 命令名"，其他显示参数
    private func detail(_ presentation: BindingPresentation) -> String {
        if presentation.category == .features {
            let parts = [presentation.manifest?.displayName, presentation.descriptor?.title].compactMap(\.self)
            return parts.joined(separator: " · ")
        }
        let arguments = binding.arguments.sorted { $0.key < $1.key }
            .compactMap { _, value -> String? in
                value.stringValue ?? value.boolValue.map { $0 ? "是" : "否" } ?? value.numberValue.map { "\($0)" }
            }
        return ([presentation.descriptor?.title ?? binding.command.rawValue] + arguments).joined(separator: "  ")
    }

    private var enabled: SwiftUI.Binding<Bool> {
        SwiftUI.Binding(
            get: { binding.isEnabled },
            set: { value in
                var copy = binding
                copy.isEnabled = value
                controller.runtime.bindings.upsert(copy)
            },
        )
    }
}
