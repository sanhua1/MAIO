/// 一个组合键：修饰键 + 主键。配置文件中的形式为 "fn+a"、"cmd+shift+4"、"opt+tab"。
public struct KeyChord: Sendable, Hashable {
    public let keyCode: UInt16
    public let modifiers: KeyModifiers

    public init(keyCode: UInt16, modifiers: KeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// 解析配置字符串，失败返回 nil。大小写与修饰键顺序不敏感。
    public init?(string: String) {
        let tokens = string.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyToken = tokens.last, !keyToken.isEmpty else { return nil }
        var modifiers: KeyModifiers = []
        for token in tokens.dropLast() {
            guard let modifier = KeyModifiers.aliases[token.lowercased()] else { return nil }
            modifiers.insert(modifier)
        }
        guard let code = KeyCodes.code(named: keyToken) else { return nil }
        self.init(keyCode: code, modifiers: modifiers)
    }

    /// 规范字符串（写入配置文件）。
    public var string: String {
        let parts = KeyModifiers.stringOrder.filter { modifiers.contains($0.0) }.map(\.token)
        return (parts + [KeyCodes.name(for: keyCode)]).joined(separator: "+")
    }

    /// 界面显示，例如 "fn A"、"⌘⇧4"。
    public var displayString: String {
        modifiers.symbols + KeyCodes.symbol(for: keyCode)
    }
}

extension KeyChord: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let chord = KeyChord(string: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "无法解析快捷键 \(raw)"))
        }
        self = chord
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }
}

extension KeyChord: CustomStringConvertible {
    public var description: String {
        string
    }
}
