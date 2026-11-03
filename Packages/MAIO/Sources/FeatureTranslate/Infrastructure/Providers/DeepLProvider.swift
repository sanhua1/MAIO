import Foundation

// 参考：references/pot-desktop/src/services/translate/deepl/index.jsx
/// DeepL 官方 API（Key 以 :fx 结尾时用免费版地址），或用户自建的 DeepLX 地址。
struct DeepLProvider: TranslationProvider {
    let authKey: String
    let customURL: String
    let http: HTTPClient

    private struct APIBody: Encodable {
        let text: [String]
        let target_lang: String
        let source_lang: String?
    }

    private struct APIResponse: Decodable {
        struct Item: Decodable {
            let text: String
        }

        let translations: [Item]?
        let message: String?
    }

    private struct DeepLXBody: Encodable {
        let text: String
        let source_lang: String
        let target_lang: String
    }

    private struct DeepLXResponse: Decodable {
        let data: String?
        let message: String?
    }

    func translate(_ request: TranslationRequest, onPartial _: @escaping @Sendable (String) -> Void) async throws
        -> TranslationResult {
        if !customURL.isEmpty {
            return try await translateWithDeepLX(request)
        }
        guard !authKey.isEmpty else { throw TranslationError.missingSecret("Auth Key") }
        let target = try request.targetCode(Self.code)
        let source = request.source == .auto ? nil : try request.sourceCode(Self.sourceCode)
        let body = APIBody(text: [request.text], target_lang: target, source_lang: source)
        let url = try URL.fixed("\(Self.endpoint(authKey: authKey))/v2/translate")
        let headers = ["Authorization": "DeepL-Auth-Key \(authKey)"]
        let (data, status) = try await http.dataWithStatus(.postJSON(url, body: body, headers: headers))
        if status == 403 {
            throw TranslationError.service("DeepL 认证失败（HTTP 403），请检查 Auth Key")
        }
        if status == 456 {
            throw TranslationError.service("DeepL 本月额度已用完（HTTP 456）")
        }
        let response = try HTTPClient.decodeJSON(APIResponse.self, data, status: status)
        guard let items = response.translations, (200 ..< 300).contains(status) else {
            throw TranslationError.service("DeepL 错误（HTTP \(status)）：\(response.message ?? HTTPClient.snippet(data))")
        }
        return TranslationResult(text: items.map(\.text).joined(separator: "\n"))
    }

    private func translateWithDeepLX(_ request: TranslationRequest) async throws -> TranslationResult {
        let target = try request.targetCode(Self.sourceCode)
        let source = request.source == .auto ? "auto" : try request.sourceCode(Self.sourceCode)
        let body = DeepLXBody(text: request.text, source_lang: source, target_lang: target)
        let (data, status) = try await http.dataWithStatus(.postJSON(URL.userProvided(customURL), body: body))
        let response = try HTTPClient.decodeJSON(DeepLXResponse.self, data, status: status)
        guard let text = response.data, (200 ..< 300).contains(status) else {
            throw TranslationError.service("DeepLX 错误（HTTP \(status)）：\(response.message ?? HTTPClient.snippet(data))")
        }
        return TranslationResult(text: text)
    }

    static func endpoint(authKey: String) -> String {
        authKey.hasSuffix(":fx") ? "https://api-free.deepl.com" : "https://api.deepl.com"
    }

    /// 目标语言代码（中文、英语、葡萄牙语需要区分变体）。
    static func code(_ language: Language) -> String? {
        switch language {
        case .simplifiedChinese: "ZH-HANS"
        case .traditionalChinese: "ZH-HANT"
        case .english: "EN-US"
        case .portuguese: "PT-BR"
        default: sourceCode(language)
        }
    }

    /// 源语言代码（不区分变体；`.auto` 时不传 source_lang）。
    static func sourceCode(_ language: Language) -> String? {
        switch language {
        case .auto, .vietnamese, .thai, .malay: nil
        case .simplifiedChinese, .traditionalChinese: "ZH"
        default: language.rawValue.uppercased()
        }
    }
}
