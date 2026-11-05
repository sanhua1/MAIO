import MAIOKit

/// Finder 菜单里的一项（运行时从辅助功能接口读出来）
struct FinderMenuItem: Sendable, Hashable, Identifiable {
    /// 例如 ["文件", "新建文件夹"]；子菜单会多一层
    let path: [String]
    let chord: KeyChord?
    /// 🌐 + 键（例如 🌐F 全屏），系统级，不能用 App 快捷键改
    var isGlobe = false

    var id: String {
        path.joined(separator: "›") + (chord.map { "|\($0.displayString)" } ?? "")
    }

    var title: String {
        path.last ?? ""
    }

    var menu: String {
        path.first ?? ""
    }

    var displayChord: String {
        guard let chord else { return "" }
        return isGlobe ? "🌐" + chord.modifiers.subtracting(.function).symbols + KeyCodes.symbol(for: chord.keyCode)
            : chord.displayString
    }
}

/// 菜单快捷键的两种表示：辅助功能接口的 (字符, 修饰键位, 键码)，和 App 快捷键配置（NSUserKeyEquivalents）的字符串
enum MenuShortcuts {
    /// AXMenuItemCmdModifiers 的位
    enum AXModifier {
        static let shift = 1
        static let option = 2
        static let control = 4
        static let noCommand = 8
        static let function = 16
    }

    /// 方向键、F 键等在菜单里用 NSEvent 的功能键字符（U+F700…）表示
    static let functionCharacters: [UInt32: UInt16] = {
        var table: [UInt32: UInt16] = [
            0xF700: 126,
            0xF701: 125,
            0xF702: 123,
            0xF703: 124,
            0xF728: 117,
            0xF729: 115,
            0xF72B: 119,
            0xF72C: 116,
            0xF72D: 121,
        ]
        let fKeys: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        for (index, code) in fKeys.enumerated() {
            table[0xF704 + UInt32(index)] = code
        }
        return table
    }()

    static let controlCharacters: [UInt32: UInt16] = [0x08: 51, 0x7F: 51, 0x09: 48, 0x0D: 36, 0x03: 76, 0x1B: 53, 0x20: 49]

    /// 从辅助功能接口的属性还原组合键；没有快捷键时返回 nil
    static func chord(character: String, modifiers raw: Int, virtualKey: Int?) -> (chord: KeyChord, isGlobe: Bool)? {
        var modifiers: KeyModifiers = []
        if raw & AXModifier.shift != 0 {
            modifiers.insert(.shift)
        }
        if raw & AXModifier.option != 0 {
            modifiers.insert(.option)
        }
        if raw & AXModifier.control != 0 {
            modifiers.insert(.control)
        }
        if raw & AXModifier.noCommand == 0 {
            modifiers.insert(.command)
        }
        let isGlobe = raw & AXModifier.function != 0
        if isGlobe {
            modifiers.insert(.function)
        }
        let code: UInt16? = if let virtualKey, virtualKey > 0, virtualKey < 128 {
            UInt16(virtualKey)
        } else {
            keyCode(for: character)
        }
        guard let code else { return nil }
        return (KeyChord(keyCode: code, modifiers: modifiers), isGlobe)
    }

    static func keyCode(for character: String) -> UInt16? {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return nil }
        if let code = functionCharacters[scalar.value] ?? controlCharacters[scalar.value] {
            return code
        }
        return KeyCodes.code(named: character.lowercased())
    }

    /// NSUserKeyEquivalents 的值："@" ⌘、"~" ⌥、"^" ⌃、"$" ⇧，后面跟按键字符，例如 "@$n"
    static func encode(_ chord: KeyChord) -> String? {
        var text = ""
        if chord.modifiers.contains(.command) {
            text += "@"
        }
        if chord.modifiers.contains(.option) {
            text += "~"
        }
        if chord.modifiers.contains(.control) {
            text += "^"
        }
        if chord.modifiers.contains(.shift) {
            text += "$"
        }
        guard let key = character(for: chord.keyCode) else { return nil }
        return text + key
    }

    static func decode(_ text: String) -> KeyChord? {
        var modifiers: KeyModifiers = []
        var rest = Substring(text)
        while let first = rest.first, rest.count > 1, let modifier = modifierSymbols[first] {
            modifiers.insert(modifier)
            rest = rest.dropFirst()
        }
        guard let code = keyCode(for: String(rest)) else { return nil }
        return KeyChord(keyCode: code, modifiers: modifiers)
    }

    private static let modifierSymbols: [Character: KeyModifiers] = ["@": .command, "~": .option, "^": .control, "$": .shift]

    private static func character(for keyCode: UInt16) -> String? {
        if let scalar = functionCharacters.first(where: { $0.value == keyCode })?.key
            ?? controlCharacters.first(where: { $0.value == keyCode && $0.key != 0x7F })?.key {
            return Unicode.Scalar(scalar).map { String(Character($0)) }
        }
        let name = KeyCodes.name(for: keyCode)
        return name.count == 1 ? name : nil
    }

    /// NSUserKeyEquivalents 的键：完整菜单路径，每级前面加 ESC（避免同名菜单项改错）
    static func preferenceKey(_ path: [String]) -> String {
        path.map { "\u{1B}" + $0 }.joined()
    }

    static func path(fromPreferenceKey key: String) -> [String] {
        key.hasPrefix("\u{1B}") ? key.split(separator: "\u{1B}").map(String.init) : [key]
    }

    /// 在菜单快照里按完整路径找菜单项（依次试各个语言的路径）
    static func find(_ path: MenuPath, in items: [FinderMenuItem]) -> FinderMenuItem? {
        for candidate in path.candidates {
            if let item = items.first(where: { $0.path == candidate }) {
                return item
            }
        }
        return nil
    }
}
