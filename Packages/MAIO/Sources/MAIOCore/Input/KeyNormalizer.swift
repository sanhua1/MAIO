import MAIOKit

/// 把原始键盘事件归一化为 `KeyEvent`（纯逻辑，可单测）。
///
/// Fn 的难点：系统会给方向键、F1–F12、Home/End 等键**自动**加上 Fn 标志位，
/// 所以不能只看标志位。这里通过 flagsChanged 跟踪 Fn 键（键码 63）的物理按下状态。
struct KeyNormalizer {
    // CGEventFlags 的位值（避免在纯逻辑中依赖 CoreGraphics 类型）
    static let shiftMask: UInt64 = 0x0002_0000
    static let controlMask: UInt64 = 0x0004_0000
    static let optionMask: UInt64 = 0x0008_0000
    static let commandMask: UInt64 = 0x0010_0000
    static let functionMask: UInt64 = 0x0080_0000

    private(set) var isFunctionDown = false

    mutating func normalize(kind: KeyEvent.Kind, keyCode: UInt16, flags: UInt64, isRepeat: Bool) -> KeyEvent {
        if kind == .flagsChanged, keyCode == KeyCodes.function {
            isFunctionDown = flags & Self.functionMask != 0
        }
        var modifiers: KeyModifiers = []
        if flags & Self.shiftMask != 0 {
            modifiers.insert(.shift)
        }
        if flags & Self.controlMask != 0 {
            modifiers.insert(.control)
        }
        if flags & Self.optionMask != 0 {
            modifiers.insert(.option)
        }
        if flags & Self.commandMask != 0 {
            modifiers.insert(.command)
        }
        if hasFunction(keyCode: keyCode, flags: flags) {
            modifiers.insert(.function)
        }
        return KeyEvent(kind: kind, keyCode: keyCode, modifiers: modifiers, isRepeat: isRepeat)
    }

    private func hasFunction(keyCode: UInt16, flags: UInt64) -> Bool {
        if isFunctionDown {
            return true
        }
        // 没观察到 Fn 的 flagsChanged 时（例如某些外接键盘），对"不会被自动加 Fn 位"的键信任标志位
        return flags & Self.functionMask != 0 && !KeyCodes.implicitFunctionKeys.contains(keyCode)
    }
}
