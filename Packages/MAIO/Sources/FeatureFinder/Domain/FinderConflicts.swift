import MAIOKit

/// 设置页上一条冲突提示
struct ShortcutWarning: Sendable, Hashable, Identifiable {
    enum Level: Int, Sendable, Comparable {
        /// 说明：设计如此，不影响使用
        case info
        /// 会覆盖别的功能，但这个快捷键本身能用
        case warning
        /// 这个快捷键不会生效，或者另一个会失效
        case error

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    let level: Level
    let text: String

    var id: String {
        "\(level.rawValue)|\(text)"
    }
}

/// Finder 增强的快捷键冲突（ADR-0018）。优先级从高到低：系统快捷键 → Finder 增强 → MAIO 全局快捷键 → Finder 菜单。
enum FinderConflicts {
    /// 把一个键设给 MAIO 动作时的提示
    static func forAction(
        _ action: FinderActionID, chord: KeyChord, settings: FinderSettings, menu: [FinderMenuItem],
        external: [ShortcutOccupant],
    ) -> [ShortcutWarning] {
        let key = FinderKeymap.normalized(chord)
        var warnings = external.map(externalWarningForAction)
        for other in FinderActionID.allCases where other != action {
            if let used = settings.chord(for: other), FinderKeymap.normalized(used) == key {
                warnings.append(ShortcutWarning(level: .error, text: "和「\(other.info.title)」重复，只有一个会生效"))
            }
        }
        for item in menu where item.chord.map(FinderKeymap.normalized) == key {
            warnings.append(menuWarning(for: action, item: item))
        }
        if chord.modifiers.subtracting([.shift, .function]).isEmpty, !isNavigationKey(chord) {
            warnings.append(ShortcutWarning(level: .warning, text: "没有 ⌘ ⌥ ⌃：在文件列表里按这个键本来是按名称跳转"))
        }
        return sorted(warnings)
    }

    /// 把一个键设给 Finder 原生菜单项时的提示
    static func forMenuItem(
        _ item: FinderMenuItem, chord: KeyChord, settings: FinderSettings, menu: [FinderMenuItem],
        external: [ShortcutOccupant],
    ) -> [ShortcutWarning] {
        let key = FinderKeymap.normalized(chord)
        var warnings = external.map { occupant in
            ShortcutWarning(level: .error, text: occupiedText(occupant) + "，Finder 收不到")
        }
        for action in FinderActionID.allCases {
            if let used = settings.chord(for: action), FinderKeymap.normalized(used) == key {
                let level: ShortcutWarning.Level = action == .paste ? .warning : .error
                warnings.append(ShortcutWarning(level: level, text: "被 Finder 增强的「\(action.info.title)」截走"))
            }
        }
        for other in menu where other.path != item.path && other.chord.map(FinderKeymap.normalized) == key {
            warnings.append(ShortcutWarning(level: .error, text: "和 Finder 的「\(other.title)」重复，只有一个会生效"))
        }
        return sorted(warnings)
    }

    private static func menuWarning(for action: FinderActionID, item: FinderMenuItem) -> ShortcutWarning {
        switch action {
        case .paste:
            ShortcutWarning(level: .info, text: "只在剪切之后接管；其他时候仍是 Finder 的「\(item.title)」")
        case .cut where item.title.contains("剪切") || item.title == "Cut":
            ShortcutWarning(level: .info, text: "Finder 的「\(item.title)」只对文字有效，改成剪切文件")
        default:
            ShortcutWarning(level: .warning, text: "会覆盖 Finder 的「\(item.title)」（\(item.menu)菜单）")
        }
    }

    private static func externalWarningForAction(_ occupant: ShortcutOccupant) -> ShortcutWarning {
        switch occupant.kind {
        case .system:
            ShortcutWarning(level: .error, text: occupiedText(occupant) + "，不会生效")
        case .binding:
            ShortcutWarning(level: .warning, text: "MAIO 快捷键「\(occupant.title)」在 Finder 里不会触发（Finder 增强优先）")
        case .feature:
            ShortcutWarning(level: .error, text: occupiedText(occupant))
        }
    }

    private static func occupiedText(_ occupant: ShortcutOccupant) -> String {
        switch occupant.kind {
        case .system: "被系统快捷键「\(occupant.title)」占用"
        case .binding: "被 MAIO 快捷键「\(occupant.title)」占用"
        case .feature: "被「\(occupant.title)」占用"
        }
    }

    /// 回车、退格、方向键、F 键这类不会输入文字的键
    private static func isNavigationKey(_ chord: KeyChord) -> Bool {
        let code = chord.keyCode
        return code == FinderKeymap.Key.returnKey || code == FinderKeymap.Key.delete || code == FinderKeymap.Key.forwardDelete
            || KeyCodes.implicitFunctionKeys.contains(code) || code == 48 || code == 53
    }

    private static func sorted(_ warnings: [ShortcutWarning]) -> [ShortcutWarning] {
        var seen = Set<ShortcutWarning>()
        return warnings.filter { seen.insert($0).inserted }.sorted { $0.level > $1.level }
    }
}
