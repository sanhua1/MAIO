@testable import FeatureTranslate
import Foundation
import MAIOKit
import Testing

struct TargetLanguagePolicyTests {
    @Test func `uses preferred for foreign text`() {
        #expect(TargetLanguagePolicy.target(detected: .english, preferred: .simplifiedChinese, second: .english)
            == .simplifiedChinese)
    }

    @Test func `switches to second when already in target`() {
        #expect(TargetLanguagePolicy.target(detected: .simplifiedChinese, preferred: .simplifiedChinese, second: .english)
            == .english)
        #expect(TargetLanguagePolicy.target(detected: .traditionalChinese, preferred: .simplifiedChinese, second: .english)
            == .english)
    }

    @Test func `unknown uses preferred`() {
        #expect(TargetLanguagePolicy.target(detected: nil, preferred: .japanese, second: .english) == .japanese)
    }
}

struct PromptTemplateTests {
    @Test func `fills placeholders`() {
        let request = TranslationRequest(text: "hi $to", source: .english, target: .simplifiedChinese)
        let rendered = PromptTemplate(system: "to $to from $from", user: "$text").render(request)
        #expect(rendered.system == "to Simplified Chinese from English")
        // 原文里的 $to 不能被替换
        #expect(rendered.user == "hi $to")
    }
}

struct HistoryListTests {
    private func entry(_ text: String, target: Language = .english) -> HistoryEntry {
        HistoryEntry(date: Date(), text: text, source: .simplifiedChinese, target: target, results: [])
    }

    @Test func `newest first and deduplicated`() {
        var list: [HistoryEntry] = []
        list = HistoryList.adding(entry("a"), to: list, limit: 10)
        list = HistoryList.adding(entry("b"), to: list, limit: 10)
        list = HistoryList.adding(entry("a"), to: list, limit: 10)
        #expect(list.map(\.text) == ["a", "b"])
    }

    @Test func `respects limit`() {
        var list: [HistoryEntry] = []
        for index in 0 ..< 5 {
            list = HistoryList.adding(entry("\(index)"), to: list, limit: 3)
        }
        #expect(list.map(\.text) == ["4", "3", "2"])
    }

    @Test func `search matches translations`() {
        var item = entry("hello")
        item.results = [.init(service: "Google", text: "你好")]
        #expect(item.matches("你好"))
        #expect(item.matches("HELLO"))
        #expect(!item.matches("再见"))
    }
}

struct ProviderParsingTests {
    @Test func `google sentence`() throws {
        let json = #"[[["你好世界","hello world",null,null,10]],null,"en"]"#
        let result = try GoogleProvider.parse(Data(json.utf8))
        #expect(result.text == "你好世界")
        #expect(result.dictionary == nil)
    }

    @Test func `google dictionary`() throws {
        let json = #"""
        [[["你好","hello",null,null,10],[null,null,"Nǐ hǎo","həˈlō"]],
         [["interjection",["你好!","喂!"],[]],["noun",["招呼"],[]]],"en"]
        """#
        let result = try GoogleProvider.parse(Data(json.utf8))
        #expect(result.text == "你好")
        #expect(result.dictionary?.phonetics == ["/həˈlō/"])
        #expect(result.dictionary?.meanings.map(\.partOfSpeech) == ["interjection", "noun"])
    }

    @Test func `bing credentials from page`() throws {
        let page = #"""
        <div id="rich_tta" data-iid="translator.5023"></div>
        <script>_G={IG:"7B456D0E8E78409880A6D5829DAB4889",x:1};
        var params_AbusePreventionHelper = [1793662104109,"8HQLLI6f8J2t",3600000];</script>
        """#
        let now = Date(timeIntervalSince1970: 0)
        let credentials = try #require(BingSession.parse(page: page, host: "cn.bing.com", now: now))
        #expect(credentials.ig == "7B456D0E8E78409880A6D5829DAB4889")
        #expect(credentials.iid == "translator.5023")
        #expect(credentials.key == "1793662104109")
        #expect(credentials.token == "8HQLLI6f8J2t")
        #expect(credentials.expiresAt == now.addingTimeInterval(3300))
    }

    @Test func `open AI endpoint`() throws {
        #expect(try OpenAICompatibleProvider.endpoint("https://api.deepseek.com").absoluteString
            == "https://api.deepseek.com/chat/completions")
        #expect(try OpenAICompatibleProvider.endpoint("api.openai.com/v1/").absoluteString
            == "https://api.openai.com/v1/chat/completions")
        #expect(try OpenAICompatibleProvider.endpoint("http://localhost:11434/v1/chat/completions").absoluteString
            == "http://localhost:11434/v1/chat/completions")
    }

    @Test func `strips triple quotes`() {
        #expect(OpenAICompatibleProvider.stripQuotes("\"\"\"\n你好\n\"\"\"") == "你好")
        #expect(OpenAICompatibleProvider.stripQuotes("  你好 ") == "你好")
    }
}

struct ServiceConfigTests {
    @Test func `defaults enable only free services`() {
        let enabled = ServiceConfig.defaults.filter(\.isEnabled).map(\.kind)
        #expect(enabled == [.google, .bing, .transmart])
    }

    @Test func `option falls back to default`() {
        var config = ServiceConfig.make(kind: .google, id: "g")
        #expect(config.option("baseURL") == "https://translate.googleapis.com")
        config.options["baseURL"] = "  "
        #expect(config.option("baseURL") == "https://translate.googleapis.com")
        config.options["baseURL"] = "https://mirror.example"
        #expect(config.option("baseURL") == "https://mirror.example")
    }

    @Test func `every kind has spec`() {
        for kind in ProviderKind.allCases {
            #expect(!kind.spec.displayName.isEmpty)
        }
    }
}

struct TranslateSettingsMigrationTests {
    @Test func `follow mouse becomes center`() throws {
        var json = JSONValue.object(["windowPosition": .string("followMouse")])
        try TranslateSettings.migrate(&json, from: 1)
        #expect(json.objectValue?["windowPosition"] == .string("center"))
        var remembered = JSONValue.object(["windowPosition": .string("remember")])
        try TranslateSettings.migrate(&remembered, from: 1)
        #expect(remembered.objectValue?["windowPosition"] == .string("remember"))
        #expect(TranslateSettings().windowPosition == .center)
    }
}
