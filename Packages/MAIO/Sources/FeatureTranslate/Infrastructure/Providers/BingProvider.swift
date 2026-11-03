import Foundation

/// 必应翻译（网页翻译器 bing.com/translator 的接口，免费、无需 Key、国内直连）。
/// 流程：打开翻译器页面拿到 IG / IID / key / token 和 cookie，之后用它们调用 ttranslatev3。凭证缓存到过期为止。
/// 注意：Edge 浏览器的 edge.microsoft.com/translate/auth 接口已失效（2026-11 实测 404），不要再用。
struct BingProvider: TranslationProvider {
    let session: BingSession

    func translate(_ request: TranslationRequest, onPartial _: @escaping @Sendable (String) -> Void) async throws
        -> TranslationResult {
        guard let target = Self.code(request.target), target != "auto-detect" else {
            throw TranslationError.unsupportedLanguage(request.target)
        }
        let source = Self.code(request.source) ?? "auto-detect"
        return try await TranslationResult(text: session.translate(request.text, from: source, to: target))
    }

    static func code(_ language: Language) -> String? {
        switch language {
        case .auto: "auto-detect"
        case .simplifiedChinese: "zh-Hans"
        case .traditionalChinese: "zh-Hant"
        default: language.rawValue
        }
    }
}

/// 必应网页凭证与 cookie。整个功能共用一个（由 ProviderFactory 持有）。
actor BingSession {
    struct Credentials {
        let host: String
        let ig: String
        let iid: String
        let key: String
        let token: String
        let expiresAt: Date
    }

    private struct Item: Decodable {
        struct Translation: Decodable {
            let text: String
        }

        let translations: [Translation]
    }

    private let http: HTTPClient
    private var credentials: Credentials?
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        + "(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"

    init() {
        // 独立的 cookie 存储：必应校验 cookie 与 token 是否来自同一会话
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
        http = HTTPClient(session: URLSession(configuration: configuration))
    }

    /// 提前获取凭证（第一次打开必应翻译页面约需 2～3 秒），让第一次翻译不用等
    func prewarm() async {
        _ = try? await current()
    }

    func translate(_ text: String, from: String, to: String) async throws -> String {
        do {
            return try await attempt(text, from: from, to: to, credentials: current())
        } catch TranslationError.badResponse {
            // 凭证可能已失效：刷新后重试一次
            credentials = nil
            return try await attempt(text, from: from, to: to, credentials: current())
        }
    }

    private func attempt(_ text: String, from: String, to: String, credentials: Credentials) async throws -> String {
        var components = URLComponents()
        components.scheme = "https"
        components.host = credentials.host
        components.path = "/ttranslatev3"
        components.queryItems = [
            URLQueryItem(name: "isVertical", value: "1"), URLQueryItem(name: "IG", value: credentials.ig),
            URLQueryItem(name: "IID", value: credentials.iid),
        ]
        guard let url = components.url else { throw TranslationError.service("必应地址无效") }
        let request = URLRequest.postForm(url, fields: [
            ("fromLang", from), ("to", to), ("text", text),
            ("token", credentials.token), ("key", credentials.key),
        ])
        let data = try await http.data(request)
        guard let items = try? JSONDecoder().decode([Item].self, from: data), let first = items.first?.translations.first
        else {
            throw TranslationError.badResponse(HTTPClient.snippet(data))
        }
        return first.text
    }

    private func current() async throws -> Credentials {
        if let credentials, credentials.expiresAt > Date() {
            return credentials
        }
        guard let url = URL(string: "https://www.bing.com/translator") else { throw TranslationError.service("必应地址无效") }
        let (data, response) = try await http.session.data(for: .get(url))
        try HTTPClient.check(response, body: data)
        let page = (String(bytes: data, encoding: .utf8) ?? "")
        let host = response.url?.host() ?? "www.bing.com"
        guard let parsed = Self.parse(page: page, host: host) else {
            throw TranslationError.service("无法从必应翻译页面获取凭证（页面结构可能已变化）")
        }
        credentials = parsed
        return parsed
    }

    static func parse(page: String, host: String, now: Date = Date()) -> Credentials? {
        guard let ig = capture(#"IG:"([A-Za-z0-9]+)""#, in: page),
              let iid = capture(#"data-iid="(translator\.[0-9]+)""#, in: page),
              let helper = capture(#"params_AbusePreventionHelper\s*=\s*\[([^\]]+)\]"#, in: page)
        else { return nil }
        let parts = helper.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) }
        guard parts.count >= 2 else { return nil }
        let lifetime = parts.count > 2 ? (Double(parts[2]) ?? 3_600_000) / 1000 : 3600
        // 提前 5 分钟过期，避免用到快失效的 token
        return Credentials(
            host: host, ig: ig, iid: iid, key: parts[0], token: parts[1],
            expiresAt: now.addingTimeInterval(max(60, lifetime - 300)),
        )
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }
}
