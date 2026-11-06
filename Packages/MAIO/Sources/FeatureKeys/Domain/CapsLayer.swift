import MAIOKit

/// Caps 层里一个键做什么
enum LayerAction: Codable, Sendable, Hashable {
    /// 发出一个键或组合键（按住 Caps 时按下的 ⇧⌃⌥⌘ 会叠加上去）
    case keys(KeyChord)
    /// 执行一个 MAIO 命令
    case command(CommandID)
    /// 换成另一个键（`HIDKey.name`）。全局改键里在 HID 层做；层里按它的虚拟键码改发
    case hidKey(String)
}

/// Caps 层的一条映射
struct LayerEntry: Codable, Sendable, Hashable {
    /// 层里按的键（只看键码，不带修饰键）
    var key: KeyChord
    var action: LayerAction
}

extension LayerEntry {
    /// 默认层 = 用户原来 Karabiner 的配置：WASD 方向、QE 翻页、XC 行首 / 行尾
    static let defaults: [LayerEntry] = [
        ("w", "up"), ("a", "left"), ("s", "down"), ("d", "right"),
        ("q", "pageup"), ("e", "pagedown"), ("x", "cmd+left"), ("c", "cmd+right"),
    ].compactMap { from, to in
        guard let key = KeyChord(string: from), let chord = KeyChord(string: to) else { return nil }
        return LayerEntry(key: key, action: .keys(chord))
    }
}

/// Caps 层和全局改键的按键决定。纯逻辑，tap 线程上调用。
struct CapsLayer: Sendable {
    /// 在层里按下、还没再普通按下过的键：Caps 先松开时，这些键按住产生的重复仍然按层处理
    private var heldInLayer: Set<UInt16> = []

    struct Result: Equatable {
        var decision: KeyFilterDecision
        /// 要在主线程执行的命令
        var command: CommandID?
    }

    /// `map` 是 Caps 层，`global` 是不在层里时的全局改键（event tap 层那部分）
    mutating func decide(
        _ event: KeyEvent, capsHeld: Bool, map: [UInt16: LayerAction], global: [UInt16: LayerAction] = [:],
    ) -> Result {
        let pass = Result(decision: .pass)
        guard event.kind == .down else { return pass }
        let inLayer: Bool
        if event.isRepeat {
            inLayer = heldInLayer.contains(event.keyCode)
        } else {
            inLayer = capsHeld
            if capsHeld {
                heldInLayer.insert(event.keyCode)
            } else {
                heldInLayer.remove(event.keyCode)
            }
        }
        guard let action = inLayer ? map[event.keyCode] : global[event.keyCode] else { return pass }
        return Self.result(action, for: event)
    }

    private static func result(_ action: LayerAction, for event: KeyEvent) -> Result {
        switch action {
        case let .keys(chord):
            return Result(decision: .replace(KeyChord(keyCode: chord.keyCode, modifiers: chord.modifiers.union(event.modifiers))))
        case let .command(id):
            // 按住不重复执行
            return Result(decision: .consume, command: event.isRepeat ? nil : id)
        case let .hidKey(name):
            guard let code = HIDKey.named(name)?.keyCode else { return Result(decision: .consume) }
            return Result(decision: .replace(KeyChord(keyCode: code, modifiers: event.modifiers)))
        }
    }
}
