/// 从正则表达式里找出"匹配的名称里一定会出现"的最长一段普通文字（小写），用来先在名称块里粗筛。
/// 只处理简单情况：有顶层的 `|` 就放弃（返回空，退回逐条检查）；括号里的内容可能整组可选，不算。
/// `^readme\.md$` → `readme.md`；`report.*2025` → `report`；`colou?r` → `colo`。
struct RegexLiteral {
    private let characters: [Character]
    private var index = 0
    private var depth = 0
    private var runs: [String] = []
    private var current = ""

    static func required(in pattern: String) -> [UInt8] {
        var scanner = RegexLiteral(characters: Array(pattern))
        guard scanner.scan() else { return [] }
        return scanner.runs.max { $0.count < $1.count }.map(ByteText.fold) ?? []
    }

    /// 扫完返回 true；遇到顶层 `|` 返回 false
    private mutating func scan() -> Bool {
        while index < characters.count {
            let character = characters[index]
            switch character {
            case "|" where depth == 0: return false
            case "\\": escape()
            case "(": depth += 1; breakRun()
            case ")": depth -= 1; breakRun()
            case "[": breakRun(); skip(until: "]")
            case "?", "*", "{": optionalPrevious(character)
            case "+", ".", "^", "$": breakRun()
            default: if depth == 0 {
                    current.append(character)
                }
            }
            index += 1
        }
        breakRun()
        return true
    }

    private mutating func breakRun() {
        runs.append(current)
        current = ""
    }

    /// `\.` `\-` 这类转义的标点是普通字符；`\d` `\w` 等是字符类，打断当前这段
    private mutating func escape() {
        let next = index + 1 < characters.count ? characters[index + 1] : nil
        if let next, next.isPunctuation || next.isSymbol, depth == 0 {
            current.append(next)
        } else {
            breakRun()
        }
        index += 1
    }

    /// `?` `*` `{n,m}`：前一个字符可以不出现，从当前这段里去掉
    private mutating func optionalPrevious(_ character: Character) {
        if !current.isEmpty {
            current.removeLast()
        }
        breakRun()
        if character == "{" {
            skip(until: "}")
        }
    }

    private mutating func skip(until closing: Character) {
        while index < characters.count, characters[index] != closing {
            index += characters[index] == "\\" ? 2 : 1
        }
    }
}
