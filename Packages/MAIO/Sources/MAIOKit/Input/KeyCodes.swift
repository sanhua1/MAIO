/// 虚拟键码（ANSI 布局）与名称的对照表。名称用于配置文件，符号用于界面显示。
public enum KeyCodes {
    public static let tab: UInt16 = 48
    public static let escape: UInt16 = 53
    public static let delete: UInt16 = 51
    /// Fn / 🌐 键本身
    public static let function: UInt16 = 63

    /// 修饰键本身的键码，按下它们时产生 flagsChanged 而不是 keyDown。
    public static let modifierKeys: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    /// 系统会自动给这些键附加 Fn 标志位，所以不能凭标志位判断用户是否按了 Fn。
    public static let implicitFunctionKeys: Set<UInt16> = Set(
        [115, 116, 117, 119, 121, 123, 124, 125, 126, 114] + functionKeyCodes.map(\.code),
    )

    static let functionKeyCodes: [(name: String, code: UInt16)] = [
        ("f1", 122), ("f2", 120), ("f3", 99), ("f4", 118), ("f5", 96), ("f6", 97), ("f7", 98),
        ("f8", 100), ("f9", 101), ("f10", 109), ("f11", 103), ("f12", 111), ("f13", 105),
        ("f14", 107), ("f15", 113), ("f16", 106), ("f17", 64), ("f18", 79), ("f19", 80), ("f20", 90),
    ]

    static let named: [(name: String, code: UInt16, symbol: String?)] = {
        let letters: [(String, UInt16)] = [
            ("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7), ("c", 8),
            ("v", 9), ("b", 11), ("q", 12), ("w", 13), ("e", 14), ("r", 15), ("y", 16), ("t", 17),
            ("o", 31), ("u", 32), ("i", 34), ("p", 35), ("l", 37), ("j", 38), ("k", 40), ("n", 45), ("m", 46),
        ]
        let digits: [(String, UInt16)] = [
            ("1", 18), ("2", 19), ("3", 20), ("4", 21), ("6", 22), ("5", 23),
            ("9", 25), ("7", 26), ("8", 28), ("0", 29),
        ]
        let punctuation: [(String, UInt16)] = [
            ("=", 24), ("-", 27), ("]", 30), ("[", 33), ("'", 39), (";", 41), ("\\", 42),
            (",", 43), ("/", 44), (".", 47), ("`", 50),
        ]
        let special: [(String, UInt16, String)] = [
            ("return", 36, "↩"), ("tab", 48, "⇥"), ("space", 49, "Space"), ("delete", 51, "⌫"),
            ("escape", 53, "⎋"), ("help", 114, "Help"), ("home", 115, "↖"), ("pageup", 116, "⇞"),
            ("forwarddelete", 117, "⌦"), ("end", 119, "↘"), ("pagedown", 121, "⇟"),
            ("left", 123, "←"), ("right", 124, "→"), ("down", 125, "↓"), ("up", 126, "↑"),
        ]
        return letters.map { ($0.0, $0.1, nil) } + digits.map { ($0.0, $0.1, nil) }
            + punctuation.map { ($0.0, $0.1, nil) } + special.map { ($0.0, $0.1, Optional($0.2)) }
            + functionKeyCodes.map { ($0.name, $0.code, $0.name.uppercased()) }
    }()

    static let codeByName: [String: UInt16] = Dictionary(
        named.map { ($0.name, $0.code) } + [("esc", 53), ("enter", 36), ("backspace", 51)],
        uniquingKeysWith: { first, _ in first },
    )
    static let entryByCode: [UInt16: (name: String, symbol: String?)] = Dictionary(
        named.map { ($0.code, ($0.name, $0.symbol)) },
        uniquingKeysWith: { first, _ in first },
    )

    public static func code(named name: String) -> UInt16? {
        let lower = name.lowercased()
        if let code = codeByName[lower] {
            return code
        }
        if lower.hasPrefix("key"), let raw = UInt16(lower.dropFirst(3)) {
            return raw
        }
        return nil
    }

    public static func name(for code: UInt16) -> String {
        entryByCode[code]?.name ?? "key\(code)"
    }

    public static func symbol(for code: UInt16) -> String {
        guard let entry = entryByCode[code] else { return "#\(code)" }
        return entry.symbol ?? entry.name.uppercased()
    }
}
