import Foundation

/// 一个条目可以被搜到的名称，预先处理好（建目录时算一次，搜索时不再转换）。
///
/// 每个名称拆成若干"词"：英文按空格、符号、大小写变化、字母和数字的交界拆开；每个汉字单独一个词。
/// 每个词有几种写法：英文词就是它自己；汉字是字本身加上各个拼音读音。
/// 匹配时每个词可以写全、只写第一个字母、或者（最后一个词）只写开头，所以
/// `wx`、`weixin`、`wxin`、`微x` 都能找到"微信"，`vsc` 能找到"Visual Studio Code"。
struct SearchKeys: Sendable, Equatable {
    struct Name: Sendable, Equatable {
        /// 小写、NFC
        let text: String
        /// 每个词的各种写法
        let tokens: [[[Character]]]
    }

    let names: [Name]

    static let empty = SearchKeys(names: [])

    init(names: [Name]) {
        self.names = names
    }

    /// 多个名称（显示名、英文名、文件名……），去掉重复的
    init(_ rawNames: [String]) {
        var seen = Set<String>()
        var names: [Name] = []
        for raw in rawNames {
            let text = Self.normalize(raw)
            guard !text.isEmpty, seen.insert(text).inserted else { continue }
            names.append(Name(text: text, tokens: Self.tokens(of: raw)))
        }
        self.init(names: names)
    }

    /// 搜索用的统一形式：小写、Unicode NFC（macOS 的文件名可能是 NFD）、合并连续空白
    static func normalize(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// 拆词。大小写变化要看原文，所以在小写之前拆。
    static func tokens(of raw: String) -> [[[Character]]] {
        var tokens: [[[Character]]] = []
        var word: [Character] = []
        func flush() {
            if !word.isEmpty {
                tokens.append([Array(String(word).lowercased())])
            }
            word.removeAll()
        }
        for character in raw.precomposedStringWithCanonicalMapping {
            if let scalar = character.unicodeScalars.first, Pinyin.isHan(scalar) {
                flush()
                tokens.append([[character]] + Pinyin.readings(of: character).map(Array.init))
            } else if character.isLetter || character.isNumber {
                if let last = word.last, isBoundary(between: last, and: character) {
                    flush()
                }
                word.append(character)
            } else {
                flush()
            }
        }
        flush()
        return tokens
    }

    /// 词的分界：小写 → 大写（studioCode）、字母 ↔ 数字（Office2024）
    private static func isBoundary(between previous: Character, and next: Character) -> Bool {
        if previous.isLowercase, next.isUppercase {
            return true
        }
        return previous.isNumber != next.isNumber
    }
}
