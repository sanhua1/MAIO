// 参考：references/oil-find/Sources/COilFind/coilfind.c（sift_match_quality，MIT）
/// 文件名和查询词的匹配质量：
/// 4 = 完全相同或去掉扩展名后相同；3 = 名称开头；2 = 词的开头；1 = 包含；0 = 不包含
enum NameMatch {
    static func quality(_ name: ArraySlice<UInt8>, _ term: [UInt8]) -> Int {
        guard !term.isEmpty, term.count <= name.count else { return 0 }
        var best = 0
        var index = name.startIndex
        let last = name.endIndex - term.count
        while index <= last {
            if name[index] == term[0], name[index ..< index + term.count].elementsEqual(term) {
                best = max(best, quality(of: index, in: name, length: term.count))
                if best >= 2 {
                    break
                }
            }
            index += 1
        }
        return best
    }

    private static func quality(of index: Int, in name: ArraySlice<UInt8>, length: Int) -> Int {
        if index == name.startIndex {
            let rest = name[(index + length)...]
            if rest.isEmpty || (rest.first == UInt8(ascii: ".") && !rest.dropFirst().contains(UInt8(ascii: "."))) {
                return 4
            }
            return 3
        }
        return isBoundary(before: name[index - 1], at: name[index]) ? 2 : 1
    }

    private static let separators = Set(" -_.([+,".utf8)

    private static func isBoundary(before previous: UInt8, at current: UInt8) -> Bool {
        if separators.contains(previous) {
            return true
        }
        let isDigit = { (byte: UInt8) in byte &- UInt8(ascii: "0") < 10 }
        let isLetter = { (byte: UInt8) in byte &- UInt8(ascii: "a") < 26 }
        return (previous < 0x80 && current >= 0x80) || (isDigit(previous) && isLetter(current))
            || (isLetter(previous) && isDigit(current))
    }
}
