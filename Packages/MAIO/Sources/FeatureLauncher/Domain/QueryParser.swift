import Foundation

/// 解析时需要的外部信息（相对日期、`~`）
struct QueryContext {
    var now: Date
    var home: String
    var calendar = Calendar.current
}

/// Everything 兼容的查询语法（参考 Cardinal cardinal-syntax/src/lib.rs、doc/pub/search-syntax.md）：
/// - 空格 = 并且；`|` 或 `OR` = 或；`!` 或 `NOT` = 不要；`( )` 分组。优先级：`!` > `|` > 空格，所以 `a b|c` = `a 并且 (b 或 c)`；
/// - `"…"` 短语（里面的空格、`*`、`/` 都是普通文字）；
/// - `*` `?` 通配符匹配整个名称；带 `/` 按路径段匹配；
/// - `过滤器:值`，见 `QueryFilters`。
/// 写错的地方不报错：括号不配对就当它配上了，不认识的过滤器当普通文字。
struct QueryParser {
    enum Token: Equatable {
        /// `prefix` 是引号之前的部分（判断过滤器用），`quoted` 是引号里的内容（没有引号时为 nil）
        case word(prefix: String, quoted: String?)
        case open
        case close
        case or
        case not
    }

    private var tokens: [Token]
    private var position = 0
    let context: QueryContext

    init(text: String, context: QueryContext) {
        tokens = Self.tokenize(text)
        self.context = context
    }

    mutating func parse() -> FileExpr? {
        var items: [FileExpr] = []
        while position < tokens.count {
            if let item = parseAnd() {
                items.append(item)
            }
            if position < tokens.count {
                position += 1
            } // 多出来的右括号
        }
        return Self.combine(items, as: FileExpr.all)
    }

    // MARK: 语法

    private mutating func parseAnd() -> FileExpr? {
        var items: [FileExpr] = []
        while let token = peek, token != .close {
            if token == .or {
                position += 1 // 开头或连续的 |
                continue
            }
            if let item = parseOr() {
                items.append(item)
            }
        }
        return Self.combine(items, as: FileExpr.all)
    }

    private mutating func parseOr() -> FileExpr? {
        var items: [FileExpr] = []
        if let first = parseNot() {
            items.append(first)
        }
        while peek == .or {
            position += 1
            if let next = parseNot() {
                items.append(next)
            }
        }
        return Self.combine(items, as: FileExpr.any)
    }

    private mutating func parseNot() -> FileExpr? {
        guard peek == .not else { return parsePrimary() }
        position += 1
        return parseNot().map(FileExpr.not)
    }

    private mutating func parsePrimary() -> FileExpr? {
        guard let token = peek else { return nil }
        position += 1
        switch token {
        case .open:
            let inner = parseAnd()
            if peek == .close {
                position += 1
            }
            return inner
        case let .word(prefix, quoted):
            return QueryFilters.expression(prefix: prefix, quoted: quoted, context: context)
        case .close, .or, .not:
            return nil
        }
    }

    private var peek: Token? {
        position < tokens.count ? tokens[position] : nil
    }

    private static func combine(_ items: [FileExpr], as make: ([FileExpr]) -> FileExpr) -> FileExpr? {
        items.count <= 1 ? items.first : make(items)
    }

    // MARK: 切词

    static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var scanner = WordScanner(Array(text))
        while let token = scanner.next() {
            tokens.append(token)
        }
        return tokens
    }
}

/// 逐字符切词
private struct WordScanner {
    let characters: [Character]
    var index = 0

    init(_ characters: [Character]) {
        self.characters = characters
    }

    mutating func next() -> QueryParser.Token? {
        while index < characters.count, characters[index].isWhitespace {
            index += 1
        }
        guard index < characters.count else { return nil }
        let character = characters[index]
        switch character {
        case "|": index += 1; return .or
        case "(": index += 1; return .open
        case ")": index += 1; return .close
        case "!": index += 1; return .not
        default: return word()
        }
    }

    /// 一个词：到空白、`|`、括号为止；遇到引号就读到下一个引号（中间什么都算普通文字）
    private mutating func word() -> QueryParser.Token? {
        var prefix = ""
        var quoted: String?
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                index += 1
                var inside = ""
                while index < characters.count, characters[index] != "\"" {
                    inside.append(characters[index])
                    index += 1
                }
                index += 1
                quoted = (quoted ?? "") + inside
                continue
            }
            if character.isWhitespace || "|()".contains(character) {
                break
            }
            if quoted != nil {
                quoted?.append(character)
            } else {
                prefix.append(character)
            }
            index += 1
        }
        switch (prefix, quoted) {
        case ("OR", nil): return .or
        case ("NOT", nil): return .not
        case ("AND", nil): return next()
        default: return .word(prefix: prefix, quoted: quoted)
        }
    }
}
