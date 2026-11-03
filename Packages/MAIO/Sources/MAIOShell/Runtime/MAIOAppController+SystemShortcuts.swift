import MAIOCore
import MAIOKit

/// 系统快捷键冲突的辅助方法（快捷键页、绑定编辑器、系统快捷键页共用）。
extension MAIOAppController {
    /// 已启用的绑定与哪些已启用的系统快捷键冲突。
    func systemConflicts(for binding: CommandBinding) -> [SystemShortcut] {
        guard binding.isEnabled, case let .hotkey(chord) = binding.trigger else { return [] }
        return runtime.systemShortcuts.conflicts(for: chord)
    }

    /// 是否还有已启用的 MAIO 绑定使用该系统快捷键的组合。
    func hasMAIOBinding(conflictingWithSystemShortcut id: Int) -> Bool {
        guard let shortcut = runtime.systemShortcuts.shortcuts.first(where: { $0.id == id }) else { return false }
        return runtime.bindings.bindings.contains { binding in
            guard binding.isEnabled, case let .hotkey(chord) = binding.trigger else { return false }
            return shortcut.conflicts(with: chord)
        }
    }

    /// 写入备份记录的原因，例如 "MAIO：fn A → 打开 App"。
    func reason(for binding: CommandBinding) -> String {
        let title = commandCatalog.flatMap(\.commands).first { $0.id == binding.command }?.title ?? binding.command.rawValue
        return "MAIO：\(binding.trigger.displayString) → \(binding.title ?? title)"
    }
}
