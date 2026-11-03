import Foundation

// 参考：references/pot-desktop/src/services/translate/baidu/index.jsx
/// 百度翻译开放平台·通用文本翻译。签名：md5(appid + q + salt + 密钥)。
struct BaiduProvider: TranslationProvider {
    let appID: String
    let secret: String
    let http: HTTPClient

    private struct Response: Decodable {
        struct Item: Decodable {
            let dst: String
        }

        let trans_result: [Item]?
        let error_code: LooseString?
        let error_msg: String?
    }

    func translate(_ request: TranslationRequest, onPartial _: @escaping @Sendable (String) -> Void) async throws
        -> TranslationResult {
        let target = try request.targetCode(Self.code)
        let source = try request.sourceCode(Self.code)
        let salt = SigningClock.nonce()
        let fields = [
            ("q", request.text), ("from", source), ("to", target), ("appid", appID),
            ("salt", salt), ("sign", Self.sign(appID: appID, text: request.text, salt: salt, secret: secret)),
        ]
        let url = try URL.fixed("https://fanyi-api.baidu.com/api/trans/vip/translate")
        let (data, status) = try await http.dataWithStatus(.postForm(url, fields: fields))
        let response = try HTTPClient.decodeJSON(Response.self, data, status: status)
        if let code = response.error_code, code.value != "52000" {
            throw TranslationError.service("百度翻译错误 \(code.value)：\(response.error_msg ?? "未知错误")")
        }
        guard let items = response.trans_result else { throw TranslationError.badResponse(HTTPClient.snippet(data)) }
        return TranslationResult(text: items.map(\.dst).joined(separator: "\n"))
    }

    static func sign(appID: String, text: String, salt: String, secret: String) -> String {
        Crypto.md5Hex(appID + text + salt + secret)
    }

    static func code(_ language: Language) -> String? {
        switch language {
        case .auto: "auto"
        case .simplifiedChinese: "zh"
        case .traditionalChinese: "cht"
        case .japanese: "jp"
        case .korean: "kor"
        case .french: "fra"
        case .spanish: "spa"
        case .vietnamese: "vie"
        case .arabic: "ara"
        case .malay: "may"
        case .ukrainian: "ukr"
        case .english, .german, .russian, .italian, .portuguese, .thai, .indonesian, .turkish, .polish, .dutch:
            language.rawValue
        }
    }
}
