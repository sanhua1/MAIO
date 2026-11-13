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
        "MAIO：\(binding.trigger.displayString) → \(title(of: binding))"
    }

    /// 绑定在界面上的名字：有备注用备注，否则用命令名。
    func title(of binding: CommandBinding) -> String {
        binding.title
            ?? commandCatalog.flatMap(\.commands).first { $0.id == binding.command }?.title
            ?? binding.command.rawValue
    }

    /// 其他功能在某些 App 里占用了这个绑定的组合键（ADR-0018），例如 Finder 增强在 Finder 里的改键。
    /// 返回的文字形如"Finder 增强：剪切（在 Finder 里）"
    func featureReservations(for binding: CommandBinding) -> [String] {
        guard binding.isEnabled, case let .hotkey(chord) = binding.trigger else { return [] }
        return runtime.reservations.reservations(of: chord, scope: binding.scope).map { entry in
            let name = runtime.host.manifests.first { $0.id == entry.feature }?.displayName ?? entry.feature.rawValue
            return "\(name)：\(entry.shortcut.title)\(Self.scopeDescription(entry.shortcut.scope))"
        }
    }

    private static func scopeDescription(_ scope: BindingScope) -> String {
        switch scope {
        case .global: ""
        case let .onlyIn(apps): "（在 " + apps.map(appName).joined(separator: "、") + " 里）"
        case .exceptIn: "（部分 App）"
        }
    }

    private static func appName(_ bundleID: String) -> String {
        bundleID == "com.apple.finder" ? "Finder" : bundleID
    }
}
