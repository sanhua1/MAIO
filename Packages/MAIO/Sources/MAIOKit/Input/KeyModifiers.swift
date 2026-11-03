/// 修饰键集合。`function` 即 Fn / 🌐 键。
public struct KeyModifiers: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let function = KeyModifiers(rawValue: 1 << 0)
    public static let control = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let shift = KeyModifiers(rawValue: 1 << 3)
    public static let command = KeyModifiers(rawValue: 1 << 4)

    /// 界面符号顺序（macOS 惯例：⌃⌥⇧⌘）。
    static let ordered: [(KeyModifiers, token: String, symbol: String)] = [
        (.function, "fn", "fn "),
        (.control, "ctrl", "⌃"),
        (.option, "opt", "⌥"),
        (.shift, "shift", "⇧"),
        (.command, "cmd", "⌘"),
    ]

    /// 配置字符串中的规范顺序，例如 "cmd+shift+4"、"ctrl+opt+cmd+left"。
    static let stringOrder: [(KeyModifiers, token: String)] = [
        (.function, "fn"), (.control, "ctrl"), (.option, "opt"), (.command, "cmd"), (.shift, "shift"),
    ]

    static let aliases: [String: KeyModifiers] = [
        "fn": .function, "globe": .function,
        "ctrl": .control, "control": .control, "⌃": .control,
        "opt": .option, "option": .option, "alt": .option, "⌥": .option,
        "shift": .shift, "⇧": .shift,
        "cmd": .command, "command": .command, "⌘": .command,
    ]

    public var symbols: String {
        Self.ordered.filter { contains($0.0) }.map(\.symbol).joined()
    }
}
