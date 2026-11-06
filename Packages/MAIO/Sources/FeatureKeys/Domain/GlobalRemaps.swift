import MAIOKit

/// 全局改键的一条：一个键 → 另一个键（HID 层）/ 组合键 / MAIO 命令（event tap 层）。
struct KeyRemap: Codable, Sendable, Hashable {
    /// `HIDKey.name`
    var from: String
    var action: LayerAction
    var isEnabled = true
}

/// 鼠标按钮改键：中键、侧键 → 组合键 / MAIO 命令。
struct MouseRemap: Codable, Sendable, Hashable {
    /// 2 中键、3 后退、4 前进……（CGEvent 的按钮号）
    var button: Int
    var action: LayerAction
    var isEnabled = true

    static func title(for button: Int) -> String {
        switch button {
        case 2: "中键"
        case 3: "后退键（侧键 1）"
        case 4: "前进键（侧键 2）"
        default: "按钮 \(button + 1)"
        }
    }
}

/// 把全局改键分到两层：单键换单键走 HID 层（在所有 event tap 之前，密码框里也生效，ADR-0022），其余走 event tap。
enum GlobalRemaps {
    /// HID 层的映射（全局 `UserKeyMapping`）
    static func hidPairs(_ remaps: [KeyRemap]) -> [MappingPair] {
        var seen = Set<UInt64>()
        return remaps.compactMap { remap in
            guard remap.isEnabled, case let .hidKey(name) = remap.action,
                  let from = HIDKey.named(remap.from), let to = HIDKey.named(name), seen.insert(from.usage).inserted
            else { return nil }
            return MappingPair(source: from.usage, destination: to.usage)
        }
    }

    /// event tap 层：键码 → 动作（同一个键有多条时用第一条；没有虚拟键码的键做不了）
    static func tapMap(_ remaps: [KeyRemap]) -> [UInt16: LayerAction] {
        remaps.reduce(into: [:]) { map, remap in
            guard remap.isEnabled, remap.action.isTapAction, let code = HIDKey.named(remap.from)?.keyCode, map[code] == nil
            else { return }
            map[code] = remap.action
        }
    }

    static func buttonMap(_ remaps: [MouseRemap]) -> [Int: LayerAction] {
        remaps.reduce(into: [:]) { map, remap in
            if remap.isEnabled, remap.action.isTapAction, map[remap.button] == nil {
                map[remap.button] = remap.action
            }
        }
    }
}

extension LayerAction {
    /// 组合键、命令在 event tap 层做；单键（`hidKey`）在 HID 层做
    var isTapAction: Bool {
        if case .hidKey = self {
            return false
        }
        return true
    }
}
