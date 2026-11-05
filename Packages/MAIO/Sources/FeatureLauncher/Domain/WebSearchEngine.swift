import Foundation

/// 网页搜索引擎：`关键词 + 空格 + 内容` 直接用它搜；URL 模板里的 `{query}` 换成 URL 编码后的内容。
struct WebSearchEngine: Codable, Sendable, Hashable, Identifiable {
    var name: String
    var keyword: String
    var template: String

    var id: String {
        keyword
    }

    static let placeholder = "{query}"

    static let defaults: [WebSearchEngine] = [
        WebSearchEngine(name: "Google", keyword: "g", template: "https://www.google.com/search?q={query}"),
        WebSearchEngine(name: "百度", keyword: "bd", template: "https://www.baidu.com/s?wd={query}"),
        WebSearchEngine(name: "必应", keyword: "bi", template: "https://www.bing.com/search?q={query}"),
        WebSearchEngine(name: "GitHub", keyword: "gh", template: "https://github.com/search?q={query}"),
    ]

    /// 查询参数里要编码的字符：在 URL 允许的字符之外，再去掉 `& + = ? #`
    private static let allowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&+=?#")
        return set
    }()

    func url(for text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, template.contains(Self.placeholder),
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: Self.allowed)
        else { return nil }
        return URL(string: template.replacingOccurrences(of: Self.placeholder, with: encoded))
    }
}
