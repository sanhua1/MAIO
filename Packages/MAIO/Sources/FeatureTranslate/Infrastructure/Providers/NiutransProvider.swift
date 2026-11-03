import Foundation

// 参考：references/pot-desktop/src/services/translate/niutrans/index.jsx
/// 小牛翻译开放平台·文本翻译（API Key 放在请求体里）。
struct NiutransProvider: TranslationProvider {
    let apiKey: String
    let http: HTTPClient

    private struct Body: Encodable {
        let from: String
        let to: String
        let apikey: String
        let src_text: String
    }

    private struct Response: Decodable {
        let tgt_text: String?
        let error_code: LooseString?
        let error_msg: String?
    }

    func translate(_ request: TranslationRequest, onPartial _: @escaping @Sendable (String) -> Void) async throws
        -> TranslationResult {
        let target = try request.targetCode(Self.code)
        let source = try request.sourceCode(Self.code)
        let body = Body(from: source, to: target, apikey: apiKey, src_text: request.text)
        let url = try URL.fixed("https://api.niutrans.com/NiuTransServer/translation")
        let (data, status) = try await http.dataWithStatus(.postJSON(url, body: body))
        let response = try HTTPClient.decodeJSON(Response.self, data, status: status)
        if let code = response.error_code {
            throw TranslationError.service("小牛翻译错误 \(code.value)：\(response.error_msg ?? "未知错误")")
        }
        guard let text = response.tgt_text else { throw TranslationError.badResponse(HTTPClient.snippet(data)) }
        return TranslationResult(text: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func code(_ language: Language) -> String? {
        switch language {
        case .auto: "auto"
        case .simplifiedChinese: "zh"
        case .traditionalChinese: "cht"
        default: language.rawValue
        }
    }
}
