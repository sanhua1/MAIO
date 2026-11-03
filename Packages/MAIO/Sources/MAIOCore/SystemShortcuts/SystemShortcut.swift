import MAIOKit

/// 一个系统快捷键（macOS 的 "symbolic hotkey"）。
public struct SystemShortcut: Identifiable, Sendable, Hashable {
    /// 系统内部编号（com.apple.symbolichotkeys 中的键）
    public let id: Int
    public let keyCode: UInt16
    public let modifiers: KeyModifiers
    public let isEnabled: Bool
    public let info: SystemShortcutInfo

    public init(id: Int, keyCode: UInt16, modifiers: KeyModifiers, isEnabled: Bool) {
        self.id = id
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isEnabled = isEnabled
        info = SystemShortcutKnowledge.info(id: id, keyCode: keyCode, modifiers: modifiers)
    }

    /// 方向键、F1–F12、Home/End、媒体键（亮度、音量、调度中心等，键码 > 126）的事件本身就带 Fn 标志位，
    /// 系统记录的 Fn 并不代表"按住 🌐"。
    var hasImplicitFunction: Bool {
        KeyCodes.implicitFunctionKeys.contains(keyCode) || keyCode > 126
    }

    /// 是否是真正的"按住 🌐 再按某键"的快捷键。
    public var isGlobeShortcut: Bool {
        modifiers.contains(.function) && !hasImplicitFunction
    }

    public var chord: KeyChord {
        KeyChord(keyCode: keyCode, modifiers: hasImplicitFunction ? modifiers.subtracting(.function) : modifiers)
    }

    public var displayString: String {
        isGlobeShortcut ? "🌐" + chord.modifiers.subtracting(.function).symbols + KeyCodes.symbol(for: keyCode)
            : chord.displayString
    }

    /// MAIO 的组合键按下时，是否也会触发这个系统快捷键。
    public func conflicts(with other: KeyChord) -> Bool {
        guard other.keyCode == keyCode else { return false }
        if hasImplicitFunction {
            return other.modifiers.subtracting(.function) == modifiers.subtracting(.function)
        }
        return other.modifiers == modifiers
    }
}

/// 系统快捷键的说明及其出处。
public struct SystemShortcutInfo: Sendable, Hashable {
    public enum Source: Sendable, Hashable {
        /// Apple 官方支持文档
        case appleDocs(String)
        /// 系统设置中的名称
        case systemSettings
        /// Apple 未公开说明
        case unknown
    }

    public let name: String
    public let source: Source
    /// 设置窗口中的分组
    public let category: String

    public var isDocumented: Bool {
        source != .unknown
    }
}

/// 读写系统快捷键时使用的原始数据。
public struct RawSystemShortcut: Sendable, Hashable {
    public let id: Int
    public let character: UInt16
    public let keyCode: UInt16
    /// CGEventFlags 风格的修饰位（0x800000 = Fn）
    public let modifierMask: UInt32
    public let isEnabled: Bool

    public init(id: Int, character: UInt16, keyCode: UInt16, modifierMask: UInt32, isEnabled: Bool) {
        self.id = id
        self.character = character
        self.keyCode = keyCode
        self.modifierMask = modifierMask
        self.isEnabled = isEnabled
    }

    var modifiers: KeyModifiers {
        var result: KeyModifiers = []
        if modifierMask & 0x0002_0000 != 0 {
            result.insert(.shift)
        }
        if modifierMask & 0x0004_0000 != 0 {
            result.insert(.control)
        }
        if modifierMask & 0x0008_0000 != 0 {
            result.insert(.option)
        }
        if modifierMask & 0x0010_0000 != 0 {
            result.insert(.command)
        }
        if modifierMask & 0x0080_0000 != 0 {
            result.insert(.function)
        }
        return result
    }

    var shortcut: SystemShortcut {
        SystemShortcut(id: id, keyCode: keyCode, modifiers: modifiers, isEnabled: isEnabled)
    }

    /// 写入 com.apple.symbolichotkeys 的条目格式。
    func preferenceEntry(enabled: Bool) -> JSONValue {
        [
            "enabled": .bool(enabled),
            "value": [
                "type": "standard",
                "parameters": [
                    .number(Double(character)), .number(Double(keyCode)), .number(Double(modifierMask)),
                ],
            ],
        ]
    }
}
