import Foundation

// 参考：references/oil-find/Sources/OilFindCore/Pinyin.swift、IndexStore+Mutation.swift（MIT）
/// 含汉字的文件名的备用搜索键：拼音全拼连写、拼音首字母（非汉字部分原样保留、小写）。
/// "2024年报告.docx" → `2024nianbaogao.docx`、`2024nbg.docx`。多音字只用系统给的读音。
struct AltKeys: Sendable {
    /// 汉字 → 读音（同一个字只转换一次）
    private var cache: [Character: String] = [:]

    mutating func keys(for name: String) -> [[UInt8]] {
        guard Pinyin.containsHan(name) else { return [] }
        var full = ""
        var initials = ""
        for character in name.lowercased() {
            guard let scalar = character.unicodeScalars.first, Pinyin.isHan(scalar) else {
                full.append(character)
                initials.append(character)
                continue
            }
            let reading = reading(of: character)
            full += reading
            if let first = reading.first {
                initials.append(first)
            }
        }
        return full == initials ? [Array(full.utf8)] : [Array(full.utf8), Array(initials.utf8)]
    }

    private mutating func reading(of character: Character) -> String {
        if let known = cache[character] {
            return known
        }
        let value = Pinyin.readings(of: character).first ?? ""
        cache[character] = value
        return value
    }
}
