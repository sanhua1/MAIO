import AppKit
import MAIOCore
import MAIOKit
import MAIOUI
import SwiftUI

/// 系统快捷键：冲突一览、MAIO 已禁用的（可恢复）、全部 🌐 快捷键说明。
struct SystemShortcutsPane: View {
    let controller: MAIOAppController
    @State private var showOthers = false

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
    }

    private var introSection: some View {
        Section {
            Text("MAIO 的快捷键与系统快捷键相同时，MAIO 运行期间由 MAIO 接管，系统功能不会触发；退出 MAIO 后系统快捷键恢复工作。")
            Text("如果希望退出 MAIO 后也不触发，可以在这里禁用系统快捷键。禁用前 MAIO 会自动备份原始设置，随时可以一键恢复。")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    @ViewBuilder private var conflictSection: some View {
        let pairs = conflictPairs
        if !pairs.isEmpty {
            Section("被 MAIO 快捷键覆盖（\(pairs.count)）") {
                ForEach(pairs, id: \.0.id) { binding, shortcuts in
                    HStack {
                        KeyChordLabel(text: binding.trigger.displayString)
                        Text("覆盖：" + shortcuts.map(\.info.name).joined(separator: "、"))
                        Spacer()
                        Button("禁用系统快捷键") {
                            manager.disable(shortcuts.map(\.id), reason: controller.reason(for: binding))
                        }
                    }
                }
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
                    Text("MAIO 已禁用（\(manager.backups.count)）")
                    Spacer()
                    Button("全部恢复") { manager.restoreAll() }.controlSize(.small)
                }
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
            parts.append("已没有 MAIO 快捷键使用这个组合，建议恢复")
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
            StatusBadge("已由 MAIO 禁用", tone: .neutral)
            Button("恢复") { manager.restore(shortcut.id) }
        } else if shortcut.isEnabled {
            StatusBadge("开启", tone: .positive)
            Button("禁用") { manager.disable([shortcut.id], reason: "在“系统快捷键”页手动禁用") }
        } else {
            StatusBadge("已在系统设置中关闭", tone: .neutral)
        }
    }
}
