import MAIOKit

/// 能在系统 HID 层改的键：名称、HID 用法值、macOS 虚拟键码（有的键没有，例如 F21～F24，只能在 HID 层改）。
struct HIDKey: Hashable, Sendable {
    let name: String
    let symbol: String
    let usage: UInt64
    let keyCode: UInt16?

    static func named(_ name: String) -> HIDKey? {
        byName[name]
    }

    static func with(keyCode: UInt16) -> HIDKey? {
        byKeyCode[keyCode]
    }

    static let all: [HIDKey] = letters + digits + symbols + editing + functionKeys + modifiers

    private static let byName = Dictionary(all.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    private static let byKeyCode = Dictionary(
        all.compactMap { key in key.keyCode.map { ($0, key) } }, uniquingKeysWith: { first, _ in first },
    )

    private static func key(_ name: String, _ symbol: String? = nil, _ usage: UInt64, code: UInt16? = nil) -> HIDKey {
        HIDKey(
            name: name, symbol: symbol ?? name.uppercased(), usage: HIDUsage.keyboard(usage),
            keyCode: code ?? KeyCodes.code(named: name),
        )
    }

    private static let letters = "abcdefghijklmnopqrstuvwxyz".enumerated().map { index, letter in
        key(String(letter), nil, 0x04 + UInt64(index))
    }

    private static let digits = "1234567890".enumerated().map { index, digit in key(String(digit), nil, 0x1E + UInt64(index)) }

    private static let symbols: [HIDKey] = [
        key("-", nil, 0x2D), key("=", nil, 0x2E), key("[", nil, 0x2F), key("]", nil, 0x30), key("\\", nil, 0x31),
        key(";", nil, 0x33), key("'", nil, 0x34), key("`", nil, 0x35), key(",", nil, 0x36), key(".", nil, 0x37),
        key("/", nil, 0x38),
    ]

    private static let editing: [HIDKey] = [
        key("return", "↩", 0x28), key("escape", "⎋", 0x29), key("delete", "⌫", 0x2A), key("tab", "⇥", 0x2B),
        key("space", "Space", 0x2C), key("capslock", "⇪", 0x39, code: 57), key("insert", "Insert", 0x49, code: 114),
        key("home", "Home", 0x4A), key("pageup", "PageUp", 0x4B), key("forwarddelete", "⌦", 0x4C), key("end", "End", 0x4D),
        key("pagedown", "PageDown", 0x4E), key("right", "→", 0x4F), key("left", "←", 0x50), key("down", "↓", 0x51),
        key("up", "↑", 0x52), key("printscreen", "PrintScreen", 0x46), key("scrolllock", "ScrollLock", 0x47),
        key("pause", "Pause", 0x48), key("menu", "Menu", 0x65),
    ]

    private static let functionKeys: [HIDKey] = (1 ... 24).map { number in
        let usage: UInt64 = number <= 12 ? 0x3A + UInt64(number - 1) : 0x68 + UInt64(number - 13)
        return key("f\(number)", nil, usage)
    }

    private static let modifiers: [HIDKey] = [
        key("leftcontrol", "左 ⌃", 0xE0, code: 59), key("leftshift", "左 ⇧", 0xE1, code: 56),
        key("leftoption", "左 ⌥", 0xE2, code: 58), key("leftcommand", "左 ⌘", 0xE3, code: 55),
        key("rightcontrol", "右 ⌃", 0xE4, code: 62), key("rightshift", "右 ⇧", 0xE5, code: 60),
        key("rightoption", "右 ⌥", 0xE6, code: 61), key("rightcommand", "右 ⌘", 0xE7, code: 54),
        HIDKey(name: "fn", symbol: "🌐 Fn", usage: HIDUsage.topCaseFn, keyCode: KeyCodes.function),
    ]
}
