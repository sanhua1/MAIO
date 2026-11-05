@testable import FeatureLauncher
import Foundation
import Testing

struct QueryParserTests {
    /// 2026-11-05 12:00（本地时区）
    let now: Date = {
        var components = DateComponents(year: 2026, month: 11, day: 5, hour: 12)
        components.calendar = Calendar.current
        return components.date ?? Date()
    }()

    private func parse(_ text: String) -> FileExpr? {
        FileQuery(text, now: now, home: "/Users/me")?.expression
    }

    private func name(_ text: String, _ mode: TextMatch = .contains) -> FileExpr {
        .term(.name(Array(text.utf8), mode))
    }

    @Test func `precedence not over or over and`() {
        #expect(parse("a b|c") == .all([name("a"), .any([name("b"), name("c")])]))
        #expect(parse("!a b") == .all([.not(name("a")), name("b")]))
        #expect(parse("a OR b NOT c") == .all([.any([name("a"), name("b")]), .not(name("c"))]))
        #expect(parse("(a b)|c") == .any([.all([name("a"), name("b")]), name("c")]))
    }

    @Test func `quotes, case folding and stray operators`() {
        #expect(parse("\"Application Support\"") == name("application support"))
        #expect(parse("\"*.rs\"") == name("*.rs"))
        #expect(parse("| a (b") == .all([name("a"), name("b")]))
        #expect(parse("   ") == nil)
    }

    @Test func `wildcards and path segments`() {
        #expect(parse("*.PDF") == .term(.glob(Glob(pattern: Array("*.pdf".utf8)))))
        #expect(parse("/report") == .term(.path([.text(Array("report".utf8), .prefix)])))
        #expect(parse("foo/bar/kks") == .term(.path([
            .text(Array("foo".utf8), .suffix), .text(Array("bar".utf8), .exact), .text(Array("kks".utf8), .prefix),
        ])))
        #expect(parse("src/**/a.toml") == .term(.path([
            .text(Array("src".utf8), .suffix),
            .globstar,
            .text(Array("a.toml".utf8), .prefix),
        ])))
    }

    @Test func `filters`() {
        #expect(parse("ext:pdf;.DOCX") == .term(.extensions(["pdf", "docx"])))
        #expect(parse("folder:Pictures") == .all([.term(.kind(folders: true)), name("pictures")]))
        #expect(parse("file:") == .term(.kind(folders: false)))
        #expect(parse("in:~/Documents/") == .term(.folder(path: "/Users/me/Documents", scope: .recursive)))
        #expect(parse("parent:relative") == .term(.nothing))
        #expect(parse("unknown:thing") == name("unknown:thing"))
        #expect(parse("type:picture") == .term(.extensions(FileTypes.extensions(for: "picture") ?? [])))
    }

    @Test func `size filter`() {
        #expect(parse("size:>1kb") == .term(.size(1025 ... UInt64.max)))
        #expect(parse("size:<=2mb") == .term(.size(0 ... 2 << 20)))
        #expect(parse("size:1mb..10mb") == .term(.size(1 << 20 ... 10 << 20)))
        #expect(parse("size:empty") == .term(.size(0 ... 0)))
        #expect(parse("size:!=0") == .not(.term(.size(0 ... 0))))
        #expect(parse("size:abc") == .term(.nothing))
    }

    @Test func `date filter`() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: today))
        let start = UInt32(today.timeIntervalSince1970)
        let end = UInt32(tomorrow.timeIntervalSince1970) - 1
        #expect(parse("dm:today") == .term(.modified(start ... end)))
        #expect(parse("dm:2026-11-05") == .term(.modified(start ... end)))
        #expect(parse("dm:>=2026/11/05") == .term(.modified(start ... UInt32.max)))
        #expect(parse("dm:<2026.11.05") == .term(.modified(0 ... start - 1)))
        if case let .term(.modified(range))? = parse("dm:7d") {
            #expect(range.lowerBound == UInt32(now.timeIntervalSince1970) - 7 * 86400)
        } else {
            Issue.record("dm:7d 没有解析成时间范围")
        }
        #expect(parse("dm:2026") != .term(.nothing))
        #expect(parse("dm:soon") == .term(.nothing))
    }

    @Test func `glob matching`() {
        func matches(_ pattern: String, _ name: String) -> Bool {
            Glob(pattern: Array(pattern.utf8)).matches(Array(name.utf8)[...])
        }
        #expect(matches("*.rs", "main.rs"))
        #expect(!matches("*.rs", "main.rsx"))
        #expect(matches("report-??.txt", "report-01.txt"))
        #expect(matches("a*b", "aXXb"))
        #expect(matches("合?.txt", "合同.txt"))
        #expect(!matches("a*b", "ab c"))
    }
}

struct RegexLiteralTests {
    private func literal(_ pattern: String) -> String {
        String(utf8: RegexLiteral.required(in: pattern))
    }

    @Test func `required literal`() {
        #expect(literal("^README\\.md$") == "readme.md")
        #expect(literal("report.*2025") == "report")
        #expect(literal("colou?r") == "colo")
        #expect(literal("ab{2}cdef") == "cdef")
        #expect(literal("(foo)?barbaz") == "barbaz")
        #expect(literal("[a-z]+tmp\\d") == "tmp")
        #expect(literal("cat|dog") == "")
    }
}
