import Foundation

/// `type:` 的类别 → 扩展名（参考 Cardinal doc/pub/search-syntax.md 4.4）
enum FileTypes {
    static let categories: [Set<String>: Set<String>] = [
        ["picture", "pictures", "image", "images", "photo", "photos", "pic"]: [
            "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "bmp", "tif", "tiff", "svg", "raw", "cr2", "nef", "arw", "dng",
            "ico",
            "psd",
        ],
        ["video", "videos", "movie", "movies"]: [
            "mp4",
            "mov",
            "m4v",
            "mkv",
            "avi",
            "wmv",
            "flv",
            "webm",
            "mpg",
            "mpeg",
            "3gp",
            "ts",
        ],
        ["audio", "audios", "music", "song", "songs"]: [
            "mp3",
            "m4a",
            "aac",
            "wav",
            "flac",
            "aiff",
            "aif",
            "ogg",
            "opus",
            "wma",
            "alac",
            "ape",
        ],
        ["doc", "docs", "document", "documents", "text", "office"]: [
            "txt", "md", "rtf", "doc", "docx", "pages", "odt", "pdf", "xls", "xlsx", "numbers", "ppt", "pptx", "key", "csv",
            "epub",
            "wps",
        ],
        ["presentation", "presentations", "ppt", "slides"]: ["ppt", "pptx", "key", "odp"],
        ["spreadsheet", "spreadsheets", "xls", "excel", "sheet", "sheets"]: ["xls", "xlsx", "numbers", "csv", "ods"],
        ["pdf"]: ["pdf"],
        ["archive", "archives", "compressed", "zip"]: [
            "zip",
            "rar",
            "7z",
            "tar",
            "gz",
            "tgz",
            "bz2",
            "xz",
            "zst",
            "dmg",
            "iso",
            "pkg",
        ],
        ["code", "source", "dev"]: [
            "swift", "m", "mm", "h", "c", "cc", "cpp", "hpp", "rs", "go", "py", "js", "ts", "tsx", "jsx", "java", "kt", "dart",
            "rb",
            "php", "cs", "sh", "zsh", "json", "yaml", "yml", "toml", "xml", "html", "css", "scss", "sql", "lua", "vue",
        ],
        ["exe", "exec", "executable", "executables", "program", "programs", "app", "apps"]: [
            "app",
            "exe",
            "command",
            "sh",
            "pkg",
            "dmg",
        ],
    ]

    static func extensions(for name: String) -> Set<String>? {
        let key = name.lowercased()
        return categories.first { $0.key.contains(key) }?.value
    }
}

/// `size:`：`>1gb`、`<=10kb`、`1mb..10mb`、`!=0`、关键词 empty / tiny / small / medium / large / huge / gigantic
enum SizeFilter {
    static let keywords: [String: ClosedRange<UInt64>] = [
        "empty": 0 ... 0,
        "tiny": 1 ... 10 << 10,
        "small": (10 << 10) + 1 ... 100 << 10,
        "medium": (100 << 10) + 1 ... 1 << 20,
        "large": (1 << 20) + 1 ... 16 << 20,
        "huge": (16 << 20) + 1 ... 128 << 20,
        "gigantic": (128 << 20) + 1 ... UInt64.max,
        "giant": (128 << 20) + 1 ... UInt64.max,
    ]

    static func parse(_ value: String) -> FileExpr {
        let text = value.lowercased().trimmingCharacters(in: .whitespaces)
        if let range = keywords[text] {
            return .term(.size(range))
        }
        if let dots = text.range(of: "..") {
            guard let low = bytes(text[..<dots.lowerBound]), let high = bytes(text[dots.upperBound...]), low <= high else {
                return .term(.nothing)
            }
            return .term(.size(low ... high))
        }
        return Comparison.parse(text, value: bytes).map { comparison in
            comparison.expression(lowest: 0, highest: UInt64.max, start: { $0 }, end: { $0 }, make: FileTerm.size)
        } ?? .term(.nothing)
    }

    /// "1.5mb" → 字节（1024 进制）
    static func bytes(_ text: Substring) -> UInt64? {
        let kib = 1024.0
        let units: [(String, Double)] = [
            ("kib", kib), ("mib", kib * kib), ("gib", kib * kib * kib), ("tib", kib * kib * kib * kib),
            ("kb", kib), ("mb", kib * kib), ("gb", kib * kib * kib), ("tb", kib * kib * kib * kib),
            ("k", kib), ("m", kib * kib), ("g", kib * kib * kib), ("t", kib * kib * kib * kib), ("b", 1),
        ]
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let unit = units.first { trimmed.hasSuffix($0.0) && Double(trimmed.dropLast($0.0.count)) != nil }
        let number = Double(unit.map { String(trimmed.dropLast($0.0.count)) } ?? trimmed)
        guard let number, number >= 0 else { return nil }
        return UInt64(min(number * (unit?.1 ?? 1), Double(UInt64.max / 2)))
    }
}

/// 比较符：`>`、`>=`、`<`、`<=`、`=`、`!=`，后面跟一个值（值可能是一段区间，例如"某一天"）
struct Comparison<Value: Comparable> {
    enum Operator { case greater, greaterOrEqual, less, lessOrEqual, equal, notEqual }

    let op: Operator
    let value: Value

    static func parse(_ text: String, value parse: (Substring) -> Value?) -> Comparison? {
        let operators: [(String, Operator)] = [
            (">=", .greaterOrEqual), ("<=", .lessOrEqual), ("!=", .notEqual), (">", .greater), ("<", .less), ("=", .equal),
        ]
        let match = operators.first { text.hasPrefix($0.0) }
        let rest = text.dropFirst(match?.0.count ?? 0)
        guard let value = parse(rest) else { return nil }
        return Comparison(op: match?.1 ?? .equal, value: value)
    }

    /// 值对应区间 `start(value) ... end(value)`（大小是一个点，日期是一整天）
    func expression<Bound: Comparable & Strideable>(
        lowest: Bound, highest: Bound, start: (Value) -> Bound, end: (Value) -> Bound, make: (ClosedRange<Bound>) -> FileTerm,
    ) -> FileExpr where Bound.Stride: SignedInteger {
        let low = start(value)
        let high = end(value)
        switch op {
        case .equal: return .term(make(low ... high))
        case .notEqual: return .not(.term(make(low ... high)))
        case .greaterOrEqual: return .term(make(low ... highest))
        case .lessOrEqual: return .term(make(lowest ... high))
        case .greater: return high < highest ? .term(make(high.advanced(by: 1) ... highest)) : .term(.nothing)
        case .less: return low > lowest ? .term(make(lowest ... low.advanced(by: -1))) : .term(.nothing)
        }
    }
}
