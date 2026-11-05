/// 输入和名称的匹配质量。分数越高越靠前；`nil` 表示不匹配。
///
/// | 档次 | 分数 |
/// |---|---|
/// | 名称完全相同 | 100 |
/// | 名称开头 | 90 |
/// | 从第一个词开始按词匹配（`wx` → 微信、`vsc` → Visual Studio Code） | 75 |
/// | 从中间某个词开始按词匹配（`code` → Visual Studio Code） | 60 |
/// | 名称包含 | 50 |
/// | 按顺序出现（`slk` → Slack，至少两个字符） | 20 |
///
/// 输入里有空格时，先按整体匹配；不行就要求每一段都匹配，取最低的一档再减 5。
enum MatchScore {
    static func score(_ query: String, in keys: SearchKeys) -> Int? {
        let query = SearchKeys.normalize(query)
        guard !query.isEmpty else { return nil }
        if let whole = best(query, in: keys) {
            return whole
        }
        let parts = query.split(separator: " ").map(String.init)
        guard parts.count > 1 else { return nil }
        var lowest = Int.max
        for part in parts {
            guard let value = best(part, in: keys) else { return nil }
            lowest = min(lowest, value)
        }
        return lowest - 5
    }

    private static func best(_ query: String, in keys: SearchKeys) -> Int? {
        keys.names.compactMap { score(query, name: $0) }.max()
    }

    static func score(_ query: String, name: SearchKeys.Name) -> Int? {
        if name.text == query {
            return 100
        }
        if name.text.hasPrefix(query) {
            return 90
        }
        let characters = Array(query.filter { $0 != " " })
        if let start = tokenMatchStart(characters, tokens: name.tokens) {
            return start == 0 ? 75 : 60
        }
        if name.text.contains(query) {
            return 50
        }
        if characters.count >= 2, isSubsequence(characters, of: name.text) {
            return 20
        }
        return nil
    }

    /// 从哪个词开始能按词匹配完整个输入（最早的那个）
    static func tokenMatchStart(_ query: [Character], tokens: [[[Character]]]) -> Int? {
        guard !query.isEmpty else { return nil }
        for start in tokens.indices {
            var memo: [Int: Bool] = [:]
            if matches(query, 0, tokens, start, &memo) {
                return start
            }
        }
        return nil
    }

    /// 输入从 `position` 起，能否由第 `token` 个词开始的连续几个词拼出来。
    /// 每个词可以写全，或只写第一个字母；最后剩下的输入可以只是某个词的开头。
    private static func matches(
        _ query: [Character], _ position: Int, _ tokens: [[[Character]]], _ token: Int, _ memo: inout [Int: Bool],
    ) -> Bool {
        if position == query.count {
            return true
        }
        guard token < tokens.count else { return false }
        let key = position * 1024 + token
        if let known = memo[key] {
            return known
        }
        var result = false
        let rest = query[position...]
        for form in tokens[token] where !result {
            guard let first = form.first, first == query[position] else { continue }
            if form.starts(with: rest) {
                result = true
            } else if rest.starts(with: form) {
                result = matches(query, position + form.count, tokens, token + 1, &memo)
            }
            if !result, form.count > 1 {
                result = matches(query, position + 1, tokens, token + 1, &memo)
            }
        }
        memo[key] = result
        return result
    }

    private static func isSubsequence(_ query: [Character], of text: String) -> Bool {
        var index = query.startIndex
        for character in text where index < query.endIndex && character == query[index] {
            index += 1
        }
        return index == query.endIndex
    }
}
