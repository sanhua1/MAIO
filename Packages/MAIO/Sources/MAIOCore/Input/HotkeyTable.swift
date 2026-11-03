import MAIOKit

/// 不可变的快捷键查找表：主线程构建，整体替换给 tap 线程使用。
struct HotkeyTable: Sendable {
    private let entries: [KeyChord: [CommandBinding]]

    static let empty = HotkeyTable(bindings: [], isCommandAvailable: { _ in false })

    /// 只收录：已启用、触发器为快捷键、且命令当前可用的绑定。
    init(bindings: [CommandBinding], isCommandAvailable: (CommandID) -> Bool) {
        var entries: [KeyChord: [CommandBinding]] = [:]
        for binding in bindings where binding.isEnabled && isCommandAvailable(binding.command) {
            guard case let .hotkey(chord) = binding.trigger else { continue }
            entries[chord, default: []].append(binding)
        }
        // 限定 App 的绑定优先于全局绑定
        self.entries = entries.mapValues { list in
            list.sorted { lhs, rhs in lhs.scope.priority > rhs.scope.priority }
        }
    }

    var isEmpty: Bool {
        entries.isEmpty
    }

    func match(_ chord: KeyChord, frontmost: String?) -> CommandBinding? {
        entries[chord]?.first { $0.scope.applies(to: frontmost) }
    }
}

private extension BindingScope {
    var priority: Int {
        switch self {
        case .onlyIn: 2
        case .exceptIn: 1
        case .global: 0
        }
    }
}
