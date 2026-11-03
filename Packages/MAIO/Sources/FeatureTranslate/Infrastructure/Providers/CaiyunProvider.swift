import Foundation

// 参考：references/pot-desktop/src/services/translate/caiyun/index.jsx
// 语言方向对照官方文档：https://docs.caiyunapp.com/lingocloud-api/
/// 彩云小译 API。只支持部分语言方向：目标语言限中（简/繁）、英、日、韩。
struct CaiyunProvider: TranslationProvider {
    let token: String
    let http: HTTPClient

    static let targets: Set<Language> = [.simplifiedChinese, .traditionalChinese, .english, .japanese, .korean]

    private struct Body: Encodable {
        let source: [String]
        let trans_type: String
        let detect: Bool
        let request_id = "maio"
        let media = "text"
    }

    private struct Response: Decodable {
        let target: [String]?
        let message: String?
        let error: String?
    }

    func translate(_ request: TranslationRequest, onPartial _: @escaping @Sendable (String) -> Void) async throws
        -> TranslationResult {
        guard Self.targets.contains(request.target) else { throw TranslationError.unsupportedLanguage(request.target) }
        let target = try request.targetCode(Self.code)
        let source = try request.sourceCode(Self.code)
        let body = Body(source: [request.text], trans_type: "\(source)2\(target)", detect: source == "auto")
        let url = try URL.fixed("https://api.interpreter.caiyunai.com/v1/translator")
        let headers = ["X-Authorization": "token \(token)"]
        let (data, status) = try await http.dataWithStatus(.postJSON(url, body: body, headers: headers))
        let response = try HTTPClient.decodeJSON(Response.self, data, status: status)
        if let lines = response.target, (200 ..< 300).contains(status) {
            return TranslationResult(text: lines.joined(separator: "\n"))
        }
        let detail = response.message ?? response.error ?? HTTPClient.snippet(data)
        throw TranslationError.service("彩云小译错误（HTTP \(status)）：\(detail)")
    }

    static func code(_ language: Language) -> String? {
        switch language {
        case .auto: "auto"
        case .simplifiedChinese: "zh"
        case .traditionalChinese: "zh-Hant"
        case .english, .japanese, .korean, .german, .spanish, .french, .italian, .portuguese, .russian, .turkish,
             .vietnamese:
            language.rawValue
        case .thai, .arabic, .indonesian, .malay, .polish, .dutch, .ukrainian: nil
        }
    }
}
