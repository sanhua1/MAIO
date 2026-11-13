import AppKit
import MAIOCore
import MAIOKit
import MAIOUI
import SwiftUI

/// 系统快捷键：和 MAIO 快捷键相同的（由 MAIO 接管）、已在系统中禁用的（可恢复）、全部 🌐 快捷键说明。
///
/// 两种状态要让用户分清：
/// - 由 MAIO 接管：只在 MAIO 运行时有效，系统设置没改，退出 MAIO 后系统快捷键恢复；
/// - 在系统中禁用：改了系统设置（有备份），退出 MAIO 后也不触发，要手动恢复。
struct SystemShortcutsPane: View {
    let controller: MAIOAppController
    @State private var showOthers = false
    @State private var pendingDisable: PendingDisable?
    @State private var isConfirmingDisable = false

    private var manager: SystemShortcutManager {
        controller.runtime.systemShortcuts
    }

    var body: some View {
        Form {
            if !manager.isAvailable {
                Section {
                    Label("当前系统不支持读取系统快捷键，冲突检测不可用。", systemImage: "exclamationmark.triangle")
                }
            } else {
                introSection
                conflictSection
                backupSection
                Section("系统 🌐 快捷键（\(manager.globeShortcuts.count)）") {
                    ForEach(sorted(manager.globeShortcuts)) { SystemShortcutRow(controller: controller, shortcut: $0) }
                }
                Section {
                    DisclosureGroup("其他系统快捷键（\(others.count)）", isExpanded: $showOthers) {
                        ForEach(others) { SystemShortcutRow(controller: controller, shortcut: $0) }
                    }
                } footer: {
                    Text("F1–F12、方向键本身就带 Fn 标志位，所以这里的组合不需要按住 🌐。只有当 MAIO 绑定了相同组合时才会冲突。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("系统快捷键")
        .toolbar {
            Button("刷新", systemImage: "arrow.clockwise") { manager.refresh() }
            Button("打开系统设置", systemImage: "gear") { SystemShortcutsPane.openKeyboardSettings() }
        }
        .onAppear { manager.refresh() }
        .alert(pendingDisable?.title ?? "", isPresented: $isConfirmingDisable, presenting: pendingDisable) { pending in
            Button("在系统中禁用") { manager.disable(pending.shortcutIDs, reason: pending.reason) }
            Button("取消", role: .cancel) {}
        } message: { pending in
            Text(pending.message)
        }
    }

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("MAIO 快捷键优先", systemImage: "keyboard.badge.ellipsis").font(.headline)
                Text("MAIO 的快捷键和系统快捷键相同时，MAIO 运行期间按下只会触发 MAIO 的功能，系统功能不会触发，这里显示为「由 MAIO 接管」。")
                Text("接管只在 MAIO 运行时有效，不会改动系统设置：退出 MAIO 后，系统快捷键恢复工作。")
                    .foregroundStyle(.secondary)
                Text("如果希望退出 MAIO 后它也不再触发，点「在系统中禁用」：MAIO 会先备份，再在系统设置里关闭它。之后即使 MAIO 退出也保持关闭，随时可以在本页恢复。")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder private var conflictSection: some View {
        let pairs = conflictPairs
        if !pairs.isEmpty {
            Section {
                ForEach(pairs, id: \.0.id) { binding, shortcuts in
                    HStack(spacing: 10) {
                        KeyChordLabel(text: binding.trigger.displayString).frame(minWidth: 64, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("现在触发 MAIO：" + controller.title(of: binding))
                            Text("系统原本是：" + shortcuts.map(\.info.name).joined(separator: "、"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusBadge("由 MAIO 接管", tone: .positive)
                            .help("MAIO 运行时只触发 MAIO；退出 MAIO 后系统快捷键恢复工作")
                        Button("在系统中禁用…") {
                            pendingDisable = PendingDisable(binding: binding, shortcuts: shortcuts, controller: controller)
                            isConfirmingDisable = true
                        }
                        .help("退出 MAIO 后也不让系统快捷键触发")
                    }
                }
            } header: {
                Text("与 MAIO 快捷键相同（\(pairs.count)）")
            } footer: {
                Text("这些组合现在由 MAIO 接管。只有在你希望退出 MAIO 后它们也不触发系统功能时，才需要在系统中禁用。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var backupSection: some View {
        if !manager.backups.isEmpty {
            Section {
                ForEach(manager.backups) { backup in
                    HStack {
                        KeyChordLabel(text: backup.displayString)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(backup.name)
                            Text(detail(for: backup)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("恢复") { manager.restore(backup.id) }
                    }
                }
            } header: {
                HStack {
                    Text("已在系统中禁用（\(manager.backups.count)）")
                    Spacer()
                    Button("全部恢复") { manager.restoreAll() }.controlSize(.small)
                }
            } footer: {
                Text("MAIO 在系统设置里关闭了这些快捷键，退出 MAIO 后它们也不会触发。点「恢复」回到系统原来的设置。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func detail(for backup: SystemShortcutBackup) -> String {
        let date = backup.disabledAt.formatted(date: .abbreviated, time: .shortened)
        var parts = ["\(date) 禁用"]
        if let reason = backup.reason {
            parts.append(reason)
        }
        if !controller.hasMAIOBinding(conflictingWithSystemShortcut: backup.id) {
            parts.append("已没有 MAIO 快捷键使用这个组合，按下后什么都不会发生，建议恢复")
        }
        return parts.joined(separator: " · ")
    }

    /// 已启用的 MAIO 绑定 → 与之冲突的已启用系统快捷键
    private var conflictPairs: [(CommandBinding, [SystemShortcut])] {
        controller.runtime.bindings.bindings.compactMap { binding in
            let found = controller.systemConflicts(for: binding)
            return found.isEmpty ? nil : (binding, found)
        }
    }

    private var others: [SystemShortcut] {
        sorted(manager.shortcuts.filter { !$0.isGlobeShortcut && $0.isEnabled })
    }

    private func sorted(_ list: [SystemShortcut]) -> [SystemShortcut] {
        list.sorted { ($0.info.category, $0.displayString) < ($1.info.category, $1.displayString) }
    }

    static func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct SystemShortcutRow: View {
    let controller: MAIOAppController
    let shortcut: SystemShortcut

    private var manager: SystemShortcutManager {
        controller.runtime.systemShortcuts
    }

    var body: some View {
        HStack(spacing: 10) {
            KeyChordLabel(text: shortcut.displayString).frame(minWidth: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(shortcut.info.name).foregroundStyle(shortcut.info.isDocumented ? .primary : .secondary)
                sourceLabel
            }
            Spacer()
            status
        }
    }

    @ViewBuilder private var sourceLabel: some View {
        switch shortcut.info.source {
        case let .appleDocs(url):
            if let link = URL(string: url) {
                Link("\(shortcut.info.category) · Apple 文档", destination: link).font(.caption)
            }
        case .systemSettings:
            Text("\(shortcut.info.category) · 系统设置").font(.caption).foregroundStyle(.secondary)
        case .unknown:
            Text("编号 \(shortcut.id) · Apple 未公开说明").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var status: some View {
        if manager.backup(for: shortcut.id) != nil {
            StatusBadge("已在系统中禁用", tone: .neutral)
                .help("MAIO 改了系统设置，退出 MAIO 后也不会触发")
            Button("恢复") { manager.restore(shortcut.id) }
        } else if shortcut.isEnabled {
            if controller.hasMAIOBinding(conflictingWithSystemShortcut: shortcut.id) {
                StatusBadge("由 MAIO 接管", tone: .positive)
                    .help("和某个 MAIO 快捷键相同：MAIO 运行时只触发 MAIO，退出 MAIO 后系统快捷键恢复工作")
            } else {
                StatusBadge("开启", tone: .neutral)
            }
            Button("在系统中禁用") { manager.disable([shortcut.id], reason: "在「系统快捷键」页手动禁用") }
                .help("在系统设置里关闭这个快捷键（MAIO 会先备份），退出 MAIO 后也不会触发，可随时恢复")
        } else {
            StatusBadge("已在系统设置中关闭", tone: .neutral)
        }
    }
}

/// 等待确认的"在系统中禁用"
private struct PendingDisable {
    let shortcutIDs: [Int]
    let reason: String
    let title: String
    let message: String

    @MainActor
    init(binding: CommandBinding, shortcuts: [SystemShortcut], controller: MAIOAppController) {
        shortcutIDs = shortcuts.map(\.id)
        reason = controller.reason(for: binding)
        let names = shortcuts.map { "「\($0.info.name)」" }.joined(separator: "、")
        let chord = binding.trigger.displayString
        title = "在系统中禁用\(names)？"
        message = """
        现在 MAIO 运行时按 \(chord) 已经只会触发 MAIO，禁用与否对此没有影响。

        禁用后，即使退出 MAIO，按 \(chord) 也不会再触发系统的\(names)。MAIO 会先备份系统原来的设置，随时可以在本页「已在系统中禁用」里恢复。
        """
    }
}
