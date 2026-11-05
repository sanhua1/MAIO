@testable import FeatureLauncher
import Foundation
import MAIOKit
import MAIOTesting
import Testing

@MainActor
struct LauncherTests {
    @Test func `registers declared commands`() async throws {
        let context = FakeFeatureContext(featureID: "launcher")
        // 测试里不要真的去扫整个磁盘
        var settings = LauncherSettings.defaultValue
        settings.fileSearchEnabled = false
        context.settings.save(settings)
        try await LauncherFeature(context: context).activate()
        #expect(Set(context.fakeCommands.descriptors.keys) == Set(LauncherFeature.manifest.commands.map(\.id)))
    }
}

struct MatchScoreTests {
    private func score(_ query: String, _ names: String...) -> Int? {
        MatchScore.score(query, in: SearchKeys(names))
    }

    @Test func `pinyin full initials and mixed`() {
        #expect(score("wx", "微信", "WeChat") == 75)
        #expect(score("weixin", "微信") == 75)
        #expect(score("wxin", "微信") == 75)
        #expect(score("weix", "微信") == 75)
        #expect(score("微x", "微信") == 75)
        #expect(score("wechat", "微信", "WeChat") == 100)
        #expect(score("xin", "微信") == 60)
        #expect(score("wy", "微信") == nil)
    }

    @Test func `polyphone readings`() {
        #expect(score("qqyinyue", "QQ音乐") != nil)
        #expect(score("qqyy", "QQ音乐") == 75)
        #expect(score("yinle", "QQ音乐") != nil)
    }

    @Test func `english words and acronyms`() {
        #expect(score("vsc", "Visual Studio Code") == 75)
        #expect(score("code", "Visual Studio Code") == 60)
        #expect(score("visual", "Visual Studio Code") == 90)
        #expect(score("xc", "Xcode") == 90)
        #expect(score("ode", "Xcode") == 50)
        #expect(score("slk", "Slack") == 20)
        #expect(score("ap", "Adobe Photoshop 2025") == 75)
        #expect(score("ps", "Adobe Photoshop 2025") == 20)
    }

    @Test func `multiple words must all match`() {
        #expect(score("studio code", "Visual Studio Code") == 60)
        #expect(score("code zzz", "Visual Studio Code") == nil)
    }

    @Test func `normalizes NFD and case`() {
        let nfd = "Cafe\u{301}"
        #expect(score("café", nfd) == 100)
        #expect(score("CAFÉ", "café") == 100)
    }

    @Test func `camel case and digits split words`() {
        let tokens = SearchKeys.tokens(of: "OneNote2024")
        #expect(tokens.map { String($0[0]) } == ["one", "note", "2024"])
    }
}

struct UsageBookTests {
    @Test func `decays by half life`() {
        var book = UsageBook()
        let start = Date(timeIntervalSince1970: 1_000_000)
        book.record("a", query: "x", at: start)
        #expect(abs(book.usage(of: "a", at: start.addingTimeInterval(UsageBook.halfLife)) - 0.5) < 0.0001)
    }

    @Test func `same query learns choice`() {
        var book = UsageBook()
        let now = Date()
        book.record("app:music", query: "m", at: now)
        #expect(book.bonus(for: "app:music", query: "M", at: now) > book.bonus(for: "app:mail", query: "m", at: now) + 20)
        #expect(book.bonus(for: "app:music", query: "", at: now) == 10)
    }

    @Test func `recent ordered by score`() {
        var book = UsageBook()
        let now = Date()
        book.record("a", query: "", at: now)
        book.record("b", query: "", at: now)
        book.record("b", query: "", at: now)
        #expect(book.recent(limit: 2, at: now) == ["b", "a"])
    }
}

struct LauncherQueryTests {
    let engines = WebSearchEngine.defaults

    @Test func `prefix selects source`() {
        let query = LauncherQuery.parse("a wx", selected: .all, engines: engines)
        #expect(query.source == .apps)
        #expect(query.text == "wx")
    }

    @Test func `engine keyword`() {
        let query = LauncherQuery.parse("bd 天气 预报", selected: .all, engines: engines)
        #expect(query.engine?.keyword == "bd")
        #expect(query.text == "天气 预报")
        #expect(query.engine?.url(for: query.text)?
            .absoluteString == "https://www.baidu.com/s?wd=%E5%A4%A9%E6%B0%94%20%E9%A2%84%E6%8A%A5")
    }

    @Test func `plain text uses selected tab`() {
        let query = LauncherQuery.parse("a", selected: .apps, engines: engines)
        #expect(query.source == .apps)
        #expect(query.text == "a")
        #expect(query.engine == nil)
    }

    @Test func `encodes reserved characters`() {
        let url = WebSearchEngine.defaults[0].url(for: "c++ & go")
        #expect(url?.absoluteString == "https://www.google.com/search?q=c%2B%2B%20%26%20go")
    }
}

struct LauncherRankingTests {
    private func app(_ title: String, _ names: String...) -> LauncherItem {
        .app(path: "/Applications/\(title).app", bundleID: "id.\(title)", title: title, subtitle: "", names: names)
    }

    @Test func `all mode groups apps then web`() {
        let apps = [app("微信", "WeChat"), app("网易云音乐"), app("Xcode")]
        let ranking = LauncherRanking(apps: apps, usage: UsageBook(), running: [], settings: .defaultValue, now: Date())
        let sections = ranking.sections(for: LauncherQuery(source: .all, text: "w", engine: nil))
        #expect(sections.map(\.title) == ["应用", "网页搜索"])
        #expect(sections[0].items.map(\.title).contains("微信"))
        #expect(!sections[0].items.map(\.title).contains("Xcode"))
    }

    @Test func `usage reorders equal matches`() {
        let apps = [app("Mail"), app("Music")]
        var usage = UsageBook()
        usage.record("app:id.Music", query: "m", at: Date())
        let ranking = LauncherRanking(apps: apps, usage: usage, running: [], settings: .defaultValue, now: Date())
        #expect(ranking.rank(apps, "m", limit: 5).first?.title == "Music")
    }
}
