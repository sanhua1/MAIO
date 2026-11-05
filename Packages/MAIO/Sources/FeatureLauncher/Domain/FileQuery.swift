import Foundation

/// 文件搜索条件：Everything 兼容的语法解析成的语法树（语法见 `QueryParser`，参考 Cardinal doc/pub/search-syntax.md）。
/// 所有文字都已经是小写 + NFC 的 UTF-8，和索引里的名称一致。
indirect enum FileExpr: Sendable, Equatable {
    case all([FileExpr])
    case any([FileExpr])
    case not(FileExpr)
    case term(FileTerm)
}

/// 名称和文字怎么比
enum TextMatch: Sendable, Equatable {
    case contains
    case prefix
    case suffix
    case exact

    func matches(_ name: ArraySlice<UInt8>, _ text: [UInt8]) -> Bool {
        switch self {
        case .contains: ByteText.contains(name, text)
        case .prefix: name.starts(with: text)
        case .suffix: name.count >= text.count && name.suffix(text.count).elementsEqual(text)
        case .exact: name.elementsEqual(text)
        }
    }
}

/// 一个条件
enum FileTerm: Sendable, Equatable {
    /// 名称包含 / 开头 / 结尾 / 等于
    case name([UInt8], TextMatch)
    /// 带 `*` `?` 的通配符，匹配整个名称
    case glob(Glob)
    /// 带 `/` 的路径段：最后一段匹配条目自己，前面各段依次匹配它的上级目录
    case path([PathSegment])
    case regex(String)
    /// `file:` / `folder:`
    case kind(folders: Bool)
    /// `ext:`、`type:`（扩展名，不含点，小写）
    case extensions(Set<String>)
    /// `in:`（任意深度）、`parent:`（直接子项）、`nosubfolders:`（文件夹本身和直接的文件）
    case folder(path: String, scope: FolderScope)
    /// `size:`，字节，闭区间（文件夹不参与）
    case size(ClosedRange<UInt64>)
    /// `dm:`，修改时间（秒），闭区间
    case modified(ClosedRange<UInt32>)
    /// 什么都不匹配（写错的过滤条件，例如 `size:abc`）
    case nothing
}

enum FolderScope: Sendable, Equatable {
    case recursive
    case children
    case filesOnly
}

/// 路径的一段
enum PathSegment: Sendable, Equatable {
    case text([UInt8], TextMatch)
    case glob(Glob)
    /// `**`：任意多层目录
    case globstar
}

struct FileQuery: Sendable, Equatable {
    var expression: FileExpr
    /// 排序时用来算匹配质量的词（最长的名称词）
    var primary: [UInt8]?

    /// 解析输入；什么条件都没有（空白）时返回 nil
    init?(_ text: String, foldersOnly: Bool = false, now: Date = Date(), home: String = NSHomeDirectory()) {
        var parser = QueryParser(text: text, context: QueryContext(now: now, home: home))
        guard var expression = parser.parse() else { return nil }
        if foldersOnly {
            expression = .all([.term(.kind(folders: true)), expression])
        }
        self.expression = expression
        primary = Self.longestNameText(in: expression)
    }

    init(expression: FileExpr) {
        self.expression = expression
        primary = Self.longestNameText(in: expression)
    }

    /// 主词是否只由字母组成（可能是拼音，也要扫拼音键）
    var primaryMayBePinyin: Bool {
        guard let primary, !primary.isEmpty else { return false }
        return primary.allSatisfy { $0 &- UInt8(ascii: "a") < 26 }
    }

    /// "必须满足"的名称文字里最长的那个（不进 OR、NOT）
    private static func longestNameText(in expression: FileExpr) -> [UInt8]? {
        switch expression {
        case let .all(children):
            children.compactMap(longestNameText).max { $0.count < $1.count }
        case let .term(.name(text, _)):
            text
        case let .term(.path(segments)):
            segments.last.flatMap {
                if case let .text(text, _) = $0 {
                    text
                } else {
                    nil
                }
            }
        default:
            nil
        }
    }
}

/// 字节串比较（名称都已经小写）
enum ByteText {
    static func contains(_ haystack: ArraySlice<UInt8>, _ needle: [UInt8]) -> Bool {
        guard needle.count <= haystack.count, let first = needle.first else { return needle.isEmpty }
        var index = haystack.startIndex
        let last = haystack.endIndex - needle.count
        while index <= last {
            if haystack[index] == first, haystack[index ..< index + needle.count].elementsEqual(needle) {
                return true
            }
            index += 1
        }
        return false
    }

    /// 小写 + NFC（和索引里的名称同一种形式）
    static func fold(_ text: some StringProtocol) -> [UInt8] {
        Array(String(text).lowercased().precomposedStringWithCanonicalMapping.utf8)
    }
}
