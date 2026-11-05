import Foundation

/// 一个词变成条件：过滤器（`ext:`、`size:`……）、短语、路径段、通配符、普通文字。
enum QueryFilters {
    static func expression(prefix: String, quoted: String?, context: QueryContext) -> FileExpr? {
        if let colon = prefix.firstIndex(of: ":") {
            let name = prefix[..<colon].lowercased()
            let value = String(prefix[prefix.index(after: colon)...]) + (quoted ?? "")
            if let filter = filter(name, value: value, quotedValue: quoted != nil, context: context) {
                return filter
            }
        }
        if let quoted {
            // 引号里是普通文字；引号前面如果还有字，一起算
            let text = ByteText.fold(prefix + quoted)
            return text.isEmpty ? nil : .term(.name(text, .contains))
        }
        return plain(prefix)
    }

    /// 没有引号的词
    static func plain(_ word: String) -> FileExpr? {
        guard !word.isEmpty else { return nil }
        let text = ByteText.fold(word)
        if text.contains(UInt8(ascii: "/")) {
            let segments = PathSegments.parse(text)
            return segments.isEmpty ? nil : .term(.path(segments))
        }
        if Glob.hasWildcard(text) {
            return .term(.glob(Glob(pattern: text)))
        }
        return .term(.name(text, .contains))
    }

    private static func filter(_ name: String, value: String, quotedValue: Bool, context: QueryContext) -> FileExpr? {
        switch name {
        case "file", "files": return withArgument(.kind(folders: false), value, quotedValue)
        case "folder", "folders": return withArgument(.kind(folders: true), value, quotedValue)
        case "ext":
            let list = Set(value.lowercased().split(separator: ";").map { $0.trimmingPrefix(".") }.map(String.init))
            return .term(list.isEmpty ? .nothing : .extensions(list))
        case "type": return .term(FileTypes.extensions(for: value).map(FileTerm.extensions) ?? .nothing)
        case "audio", "video", "doc", "exe", "pic", "picture", "image":
            return withArgument(FileTypes.extensions(for: name).map(FileTerm.extensions) ?? .nothing, value, quotedValue)
        case "in", "infolder": return folder(value, .recursive, context)
        case "parent": return folder(value, .children, context)
        case "nosubfolders": return folder(value, .filesOnly, context)
        case "size": return SizeFilter.parse(value)
        case "dm", "datemodified": return DateFilter.parse(value, context: context)
        case "regex": return value.isEmpty ? nil : .term(.regex(value))
        default: return nil
        }
    }

    /// `folder:Pictures` = 文件夹 并且 名称包含 pictures；`file:` 不带值时只是类型条件
    private static func withArgument(_ term: FileTerm, _ value: String, _ quoted: Bool) -> FileExpr {
        let argument = quoted ? (value.isEmpty ? nil : FileExpr.term(.name(ByteText.fold(value), .contains))) : plain(value)
        guard let argument else { return .term(term) }
        return .all([.term(term), argument])
    }

    private static func folder(_ value: String, _ scope: FolderScope, _ context: QueryContext) -> FileExpr {
        var path = value.hasPrefix("~") ? context.home + value.dropFirst() : value
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        guard path.hasPrefix("/") else { return .term(.nothing) }
        return .term(.folder(path: path.precomposedStringWithCanonicalMapping, scope: scope))
    }
}

/// 带 `/` 的词拆成路径段（Cardinal query-segmentation 的规则）：
/// 只有一段时 `/x` = 开头、`x/` = 结尾、`/x/` = 完全相同；多段时第一段默认"结尾是"（开头有 / 则完全相同）、
/// 中间各段完全相同、最后一段默认"开头是"（结尾有 / 则完全相同）。`**` 表示任意多层。
enum PathSegments {
    static func parse(_ text: [UInt8]) -> [PathSegment] {
        let slash = UInt8(ascii: "/")
        let leading = text.first == slash
        let trailing = text.last == slash
        let parts = text.split(separator: slash).map(Array.init)
        guard !parts.isEmpty else { return [] }
        return parts.enumerated().map { index, part in
            if part == Array("**".utf8) {
                return .globstar
            }
            if Glob.hasWildcard(part) {
                return .glob(Glob(pattern: part))
            }
            return .text(part, mode(index: index, count: parts.count, leading: leading, trailing: trailing))
        }
    }

    private static func mode(index: Int, count: Int, leading: Bool, trailing: Bool) -> TextMatch {
        let isFirst = index == 0
        let isLast = index == count - 1
        if isFirst, isLast {
            switch (leading, trailing) {
            case (true, true): return .exact
            case (true, false): return .prefix
            case (false, true): return .suffix
            case (false, false): return .contains
            }
        }
        if isFirst {
            return leading ? .exact : .suffix
        }
        if isLast {
            return trailing ? .exact : .prefix
        }
        return .exact
    }
}
