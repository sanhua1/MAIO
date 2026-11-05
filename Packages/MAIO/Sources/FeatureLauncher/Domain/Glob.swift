// 参考：references/oil-find/Sources/COilFind/coilfind.c（sift_glob_match，MIT）
/// 通配符：`*` 任意多个字符，`?` 一个字符（按 UTF-8 字符算，汉字也是一个），匹配整个名称。
struct Glob: Sendable, Equatable {
    let pattern: [UInt8]

    static func hasWildcard(_ text: some Collection<UInt8>) -> Bool {
        text.contains(UInt8(ascii: "*")) || text.contains(UInt8(ascii: "?"))
    }

    /// 模式里最长的一段普通文字（先用它在名称块里粗筛）
    var longestLiteral: [UInt8] {
        pattern.split { $0 == UInt8(ascii: "*") || $0 == UInt8(ascii: "?") }.max { $0.count < $1.count }.map(Array.init) ?? []
    }

    func matches(_ name: ArraySlice<UInt8>) -> Bool {
        var patternIndex = 0
        var nameIndex = name.startIndex
        var star: Int?
        var backtrack = name.startIndex
        while nameIndex < name.endIndex {
            if patternIndex < pattern.count, pattern[patternIndex] == UInt8(ascii: "*") {
                star = patternIndex
                patternIndex += 1
                backtrack = nameIndex
            } else if patternIndex < pattern.count, pattern[patternIndex] == UInt8(ascii: "?") {
                nameIndex = Self.nextCharacter(name, after: nameIndex)
                patternIndex += 1
            } else if patternIndex < pattern.count, pattern[patternIndex] == name[nameIndex] {
                nameIndex += 1
                patternIndex += 1
            } else if let star {
                backtrack = Self.nextCharacter(name, after: backtrack)
                nameIndex = backtrack
                patternIndex = star + 1
            } else {
                return false
            }
        }
        while patternIndex < pattern.count, pattern[patternIndex] == UInt8(ascii: "*") {
            patternIndex += 1
        }
        return patternIndex == pattern.count
    }

    /// 跳过一个 UTF-8 字符（首字节 + 后续的 10xxxxxx）
    private static func nextCharacter(_ text: ArraySlice<UInt8>, after index: Int) -> Int {
        var next = index + 1
        while next < text.endIndex, text[next] & 0xC0 == 0x80 {
            next += 1
        }
        return next
    }
}
