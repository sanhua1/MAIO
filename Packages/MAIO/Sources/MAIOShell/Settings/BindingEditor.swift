import MAIOCore
import MAIOKit
import SwiftUI

/// 编辑单个绑定：快捷键、命令、参数（按 ParameterSpec 自动生成表单）、生效范围。
struct BindingEditor: View {
    let controller: MAIOAppController
    let isNew: Bool
    let dismiss: () -> Void
    @State private var draft: CommandBinding
    @State private var chord: KeyChord
    @State private var scopeDraft: ScopeDraft
    /// 保存时检测到的系统快捷键冲突（非空时弹出确认框）
    @State private var pendingSystemConflicts: [SystemShortcut] = []

    init(controller: MAIOAppController, original: CommandBinding, isNew: Bool, dismiss: @escaping () -> Void) {
        self.controller = controller
        self.isNew = isNew
        self.dismiss = dismiss
        _draft = State(initialValue: original)
        if case let .hotkey(chord) = original.trigger {
            _chord = State(initialValue: chord)
        } else {
            _chord = State(initialValue: KeyChord(keyCode: 0, modifiers: .function))
        }
        _scopeDraft = State(initialValue: ScopeDraft(original.scope))
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("触发") {
                    LabeledContent("快捷键") { KeyRecorderField(controller: controller, chord: $chord) }
                    if !conflicts.isEmpty {
                        Label("与 \(conflicts.count) 个已启用的 MAIO 绑定冲突", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    ForEach(controller.featureReservations(for: result), id: \.self) { text in
                        Label("被\(text)占用：在那里优先由该功能处理，不会触发这个绑定", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    ForEach(systemConflicts) { shortcut in
                        Label(
                            "与系统快捷键「\(shortcut.info.name)」（\(shortcut.displayString)）相同：MAIO 运行时由 MAIO 接管",
                            systemImage: "globe",
                        )
                        .foregroundStyle(.orange)
                    }
                }
                Section("动作") {
                    Picker("命令", selection: $draft.command) {
                        ForEach(controller.commandCatalog) { manifest in
                            Section(manifest.displayName) {
                                ForEach(manifest.commands) { Text($0.title).tag($0.id) }
                            }
                        }
                    }
                    if let descriptor {
                        ParameterForm(parameters: descriptor.parameters, arguments: $draft.arguments)
                    }
                    TextField("备注（可选）", text: titleBinding)
                }
                ScopeSection(scope: $scopeDraft)
            }
            .formStyle(.grouped)
            footer
        }
        .frame(width: 560, height: 560)
    }

    private var footer: some View {
        HStack {
            if !isNew {
                Button("删除", role: .destructive) {
                    controller.runtime.bindings.remove(id: draft.id)
                    dismiss()
                }
            }
            Spacer()
            Button("取消", role: .cancel, action: dismiss).keyboardShortcut(.cancelAction)
            Button("保存", action: save).keyboardShortcut(.defaultAction)
        }
        .padding()
        .alert("与系统快捷键相同", isPresented: isConfirmingSystemConflict) {
            Button("保存（MAIO 运行时接管）") { commit() }
            Button("保存，并在系统中禁用") {
                controller.runtime.systemShortcuts.disable(
                    pendingSystemConflicts.map(\.id), reason: controller.reason(for: result),
                )
                commit()
            }
            Button("取消", role: .cancel) { pendingSystemConflicts = [] }
        } message: {
            Text(systemConflictMessage)
        }
    }

    private var systemConflicts: [SystemShortcut] {
        controller.systemConflicts(for: result)
    }

    private func save() {
        let found = systemConflicts
        if found.isEmpty {
            commit()
        } else {
            pendingSystemConflicts = found
        }
    }

    private func commit() {
        pendingSystemConflicts = []
        controller.runtime.bindings.upsert(result)
        dismiss()
    }

    private var isConfirmingSystemConflict: SwiftUI.Binding<Bool> {
        SwiftUI.Binding(
            get: { !pendingSystemConflicts.isEmpty },
            set: {
                if !$0 {
                    pendingSystemConflicts = []
                }
            },
        )
    }

    private var systemConflictMessage: String {
        let names = pendingSystemConflicts.map { "「\($0.info.name)」（\($0.displayString)）" }.joined(separator: "、")
        return """
        \(chord.displayString) 原本是系统快捷键\(names)。保存后，MAIO 运行时按下只会触发 MAIO，系统的功能不会触发；退出 MAIO 后系统快捷键恢复工作。

        如果希望退出 MAIO 后它也不触发，选择“保存，并在系统中禁用”：MAIO 会先备份系统原来的设置，再在系统设置里关闭它，之后可在「系统快捷键」页随时恢复。
        """
    }

    private var descriptor: CommandDescriptor? {
        controller.commandCatalog.flatMap(\.commands).first { $0.id == draft.command }
    }

    private var result: CommandBinding {
        var binding = draft
        binding.trigger = .hotkey(chord)
        binding.scope = scopeDraft.scope
        // 只保留当前命令声明过的参数
        if let descriptor {
            let keys = Set(descriptor.parameters.map(\.key))
            binding.arguments = binding.arguments.filter { keys.contains($0.key) }
        }
        return binding
    }

    private var conflicts: [CommandBinding] {
        controller.runtime.bindings.conflicts(with: result)
    }

    private var titleBinding: SwiftUI.Binding<String> {
        SwiftUI.Binding(get: { draft.title ?? "" }, set: { draft.title = $0.isEmpty ? nil : $0 })
    }
}

/// 生效范围的编辑状态。
struct ScopeDraft: Equatable {
    enum Mode: String, CaseIterable { case global = "所有 App", only = "仅在以下 App", except = "除以下 App 外" }

    var mode: Mode
    var apps: String

    init(_ scope: BindingScope) {
        switch scope {
        case .global: (mode, apps) = (.global, "")
        case let .onlyIn(list): (mode, apps) = (.only, list.joined(separator: ", "))
        case let .exceptIn(list): (mode, apps) = (.except, list.joined(separator: ", "))
        }
    }

    var scope: BindingScope {
        let list = apps.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        switch mode {
        case .global: return .global
        case .only: return list.isEmpty ? .global : .onlyIn(list)
        case .except: return list.isEmpty ? .global : .exceptIn(list)
        }
    }
}

private struct ScopeSection: View {
    @SwiftUI.Binding var scope: ScopeDraft

    var body: some View {
        Section("生效范围") {
            Picker("范围", selection: $scope.mode) {
                ForEach(ScopeDraft.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            if scope.mode != .global {
                TextField("App 的 bundle ID，用逗号分隔", text: $scope.apps)
            }
        }
    }
}
