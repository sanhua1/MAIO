import Foundation

// 参考：references/pot-desktop/src/services/translate/transmart/index.jsx
/// 腾讯交互翻译（transmart.qq.com，免费、无需 Key、国内直连）。
struct TransmartProvider: TranslationProvider {
    let http: HTTPClient

    private struct Body: Encodable {
        struct Header: Encodable {
            let fn = "auto_translation"
            let client_key = "browser-chrome-130.0.0-Mac OS-maio"
        }

        struct Source: Encodable {
            let lang: String
            let text_list: [String]
        }

        struct Target: Encodable {
            let lang: String
        }

        let header = Header()
        let type = "plain"
        let model_category = "normal"
        let source: Source
        let target: Target
    }

    private struct Response: Decodable {
        let auto_translation: [String]?
        let message: String?
    }

    func translate(_ request: TranslationRequest, onPartial _: @escaping @Sendable (String) -> Void) async throws
        -> TranslationResult {
        guard let target = Self.code(request.target), target != "auto" else {
            throw TranslationError.unsupportedLanguage(request.target)
        }
        let body = Body(
            source: Body.Source(lang: Self.code(request.source) ?? "auto", text_list: [request.text]),
            target: Body.Target(lang: target),
        )
        let url = URL(string: "https://transmart.qq.com/api/imt")
        guard let url else { throw TranslationError.service("地址无效") }
        let response = try await http.decode(Response.self, .postJSON(url, body: body))
        guard let lines = response.auto_translation else {
            throw TranslationError.service(response.message ?? "腾讯交互翻译没有返回结果")
        }
        return TranslationResult(text: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func code(_ language: Language) -> String? {
        switch language {
        case .auto: "auto"
        case .simplifiedChinese: "zh"
        case .traditionalChinese: "zh-TW"
        case .polish, .dutch, .ukrainian: nil
        default: language.rawValue
        }
    }
}
