import Foundation

/// 在索引上执行一个查询：
/// 1. 先找"候选"：从语法树里找能用名称块粗筛的文字（`AND` 里最长的那个，`OR` 各分支取并集；`!` 不能粗筛），
///    用 memmem 扫名称块（文字全是字母时也扫拼音键）；找不到能粗筛的就逐条检查全部；
/// 2. 再对每个候选完整检查整棵语法树。
struct QueryEvaluator {
    let data: IndexData
    let query: FileQuery
    /// `in:` 等过滤器的目录 → 编号（不在索引里时为 nil，什么都不匹配）
    private var folders: [String: UInt32?] = [:]
    private var regexes: [String: NSRegularExpression?] = [:]

    init(data: IndexData, query: FileQuery) {
        self.data = data
        self.query = query
        prepare(query.expression)
    }

    private mutating func prepare(_ expression: FileExpr) {
        switch expression {
        case let .all(children), let .any(children): children.forEach { prepare($0) }
        case let .not(child): prepare(child)
        case let .term(.folder(path, _)): folders[path] = data.find(path: path)
        case let .term(.regex(pattern)):
            regexes[pattern] = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        case .term: break
        }
    }

    // MARK: 候选

    /// 候选编号（升序）；nil 表示要逐条检查全部
    func candidates() -> [UInt32]? {
        candidates(for: query.expression)
    }

    private func candidates(for expression: FileExpr) -> [UInt32]? {
        switch expression {
        case let .all(children):
            // 只用一个最有选择性的子条件粗筛，其余在逐条检查时过滤
            let options = children.compactMap { child in driverText(child).map { (child, $0) } }
            guard let best = options.max(by: { $0.1 < $1.1 }) else { return nil }
            return candidates(for: best.0)
        case let .any(children):
            var union = Set<UInt32>()
            for child in children {
                guard let found = candidates(for: child) else { return nil }
                union.formUnion(found)
            }
            return union.sorted()
        case .not:
            return nil
        case let .term(term):
            return candidates(for: term)
        }
    }

    /// 这个条件能拿来粗筛的文字有多长（越长越有选择性）；不能粗筛时为 nil
    private func driverText(_ expression: FileExpr) -> Int? {
        switch expression {
        case .term(.nothing): Int.max
        case .term(.folder): 0
        case let .term(term): literals(of: term).map { $0.map(\.count).min() ?? 0 }
        case let .all(children): children.compactMap(driverText).max()
        case let .any(children): children.allSatisfy { driverText($0) != nil } ? children.compactMap(driverText).min() : nil
        case .not: nil
        }
    }

    /// 条件对应的粗筛文字（名称里一定包含其中一个）
    private func literals(of term: FileTerm) -> [[UInt8]]? {
        switch term {
        case let .name(text, _): return text.isEmpty ? nil : [text]
        case let .glob(glob): return glob.longestLiteral.isEmpty ? nil : [glob.longestLiteral]
        case let .path(segments):
            guard case let .text(text, _)? = segments.last, !text.isEmpty else { return nil }
            return [text]
        case let .extensions(list): return list.map { Array(".\($0)".utf8) }
        case let .regex(pattern):
            let literal = RegexLiteral.required(in: pattern)
            return literal.isEmpty ? nil : [literal]
        case .nothing: return []
        default: return nil
        }
    }

    private func candidates(for term: FileTerm) -> [UInt32]? {
        guard let texts = literals(of: term) else {
            if case let .folder(path, _) = term {
                return descendants(of: folders[path].flatMap(\.self))
            }
            return nil
        }
        var union = Set<UInt32>()
        for text in texts {
            union.formUnion(BlobScanner.scan(blob: data.folded, starts: data.nameStart, needle: text))
            if Self.mayBePinyin(text, term), !data.altOwner.isEmpty {
                union
                    .formUnion(BlobScanner.scan(blob: data.altKeys, starts: data.altStart, needle: text)
                        .map { data.altOwner[Int($0)] })
            }
        }
        return union.sorted()
    }

    private static func mayBePinyin(_ text: [UInt8], _ term: FileTerm) -> Bool {
        guard case .name = term else { return false }
        return text.allSatisfy { $0 &- UInt8(ascii: "a") < 26 }
    }

    /// 某个目录下的全部条目（父目录编号更小：从它往后扫一遍）
    private func descendants(of folder: UInt32?) -> [UInt32] {
        guard let folder else { return [] }
        var inside = [Bool](repeating: false, count: data.count)
        inside[Int(folder)] = true
        var result: [UInt32] = []
        for id in (folder + 1) ..< UInt32(data.count) where inside[Int(data.parents[Int(id)])] {
            inside[Int(id)] = true
            result.append(id)
        }
        return result
    }

    // MARK: 逐条检查

    func matches(_ id: UInt32) -> Bool {
        matches(id, query.expression)
    }

    private func matches(_ id: UInt32, _ expression: FileExpr) -> Bool {
        switch expression {
        case let .all(children): children.allSatisfy { matches(id, $0) }
        case let .any(children): children.contains { matches(id, $0) }
        case let .not(child): !matches(id, child)
        case let .term(term): matches(id, term)
        }
    }

    private func matches(_ id: UInt32, _ term: FileTerm) -> Bool {
        let name = data.foldedName(id)
        let isDirectory = data.flags[Int(id)] & EntryFlags.directory != 0
        switch term {
        case let .name(text, mode):
            return mode.matches(name, text) || (mode == .contains && data.altKeysContain(id, text))
        case let .glob(glob): return glob.matches(name)
        case let .path(segments): return PathChain(data: data, segments: segments).matches(id)
        case let .regex(pattern): return regexMatches(id, pattern)
        case let .kind(folders): return isDirectory == folders
        case let .extensions(list):
            // 文件夹不算，但 .app 这类包算（ext:app、type:exe 能找到应用）
            let isPackage = data.flags[Int(id)] & EntryFlags.package != 0
            return (!isDirectory || isPackage) && Self.extensionOf(name).map(list.contains) == true
        case let .folder(path, scope): return inFolder(id, folders[path].flatMap(\.self), scope, isDirectory)
        case let .size(range): return !isDirectory && range.contains(FileScanner.decodeSize(data.sizes[Int(id)]))
        case let .modified(range): return range.contains(data.mtimes[Int(id)])
        case .nothing: return false
        }
    }

    private func regexMatches(_ id: UInt32, _ pattern: String) -> Bool {
        guard let regex = regexes[pattern].flatMap(\.self) else { return false }
        let name = data.name(id)
        return regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
    }

    private func inFolder(_ id: UInt32, _ folder: UInt32?, _ scope: FolderScope, _ isDirectory: Bool) -> Bool {
        guard let folder else { return false }
        let parent = data.parents[Int(id)]
        switch scope {
        case .children: return parent == folder && id != folder
        case .filesOnly: return id == folder || (parent == folder && !isDirectory)
        case .recursive:
            var current = parent
            while current != 0 {
                if current == folder {
                    return true
                }
                current = data.parents[Int(current)]
            }
            return folder == 0 && id != 0
        }
    }

    static func extensionOf(_ name: ArraySlice<UInt8>) -> String? {
        guard let dot = name.lastIndex(of: UInt8(ascii: ".")), dot > name.startIndex else { return nil }
        return String(utf8: name[(dot + 1)...])
    }
}

/// 路径段从条目自己往上逐级匹配（最后一段对条目，前一段对父目录……）；`**` 可以跨任意多层
struct PathChain {
    let data: IndexData
    let segments: [PathSegment]

    func matches(_ id: UInt32) -> Bool {
        guard let last = segments.last else { return false }
        // 结尾是 `**`：条目必须在前面那串目录的下面（至少一层），不包括那个目录自己
        if last == .globstar {
            var current = data.parents[Int(id)]
            while true {
                if match(segments.count - 2, current) {
                    return id != 0
                }
                if current == 0 {
                    return false
                }
                current = data.parents[Int(current)]
            }
        }
        return match(segments.count - 1, id)
    }

    /// 第 `index` 段（及前面各段）能否从 `id` 这一级开始往上匹配
    private func match(_ index: Int, _ id: UInt32) -> Bool {
        if index < 0 {
            return true
        }
        let segment = segments[index]
        if segment == .globstar {
            return match(index - 1, id) || (id != 0 && match(index, data.parents[Int(id)]))
        }
        guard id != 0, matches(segment, data.foldedName(id)) else { return false }
        return match(index - 1, data.parents[Int(id)])
    }

    private func matches(_ segment: PathSegment, _ name: ArraySlice<UInt8>) -> Bool {
        switch segment {
        case let .text(text, mode): mode.matches(name, text)
        case let .glob(glob): glob.matches(name)
        case .globstar: true
        }
    }
}
