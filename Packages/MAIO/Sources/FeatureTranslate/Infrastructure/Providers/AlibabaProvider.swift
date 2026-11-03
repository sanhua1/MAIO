import Foundation

// 参考：references/pot-desktop/src/services/translate/alibaba/index.jsx
// 签名步骤对照官方文档「RPC 风格请求签名」（阿里云 API 签名机制 V1）
/// 阿里云机器翻译·通用版 TranslateGeneral（RPC 风格，签名 HMAC-SHA1 v1.0）。
struct AlibabaProvider: TranslationProvider {
    let accessKeyID: String
    let accessKeySecret: String
    let http: HTTPClient

    private struct Response: Decodable {
        struct Payload: Decodable {
            let Translated: String?
        }

        let Code: LooseString?
        let Message: String?
        let Data: Payload?
    }

    func translate(_ request: TranslationRequest, onPartial _: @escaping @Sendable (String) -> Void) async throws
        -> TranslationResult {
        let target = try request.targetCode(Self.code)
        let source = try request.sourceCode(Self.code)
        let parameters = [
            ("AccessKeyId", accessKeyID), ("Action", "TranslateGeneral"), ("Format", "JSON"),
            ("FormatType", "text"), ("Scene", "general"), ("SignatureMethod", "HMAC-SHA1"),
            ("SignatureNonce", UUID().uuidString), ("SignatureVersion", "1.0"),
            ("SourceLanguage", source), ("SourceText", request.text), ("TargetLanguage", target),
            ("Timestamp", SigningClock.iso8601(Date())), ("Version", "2018-10-12"),
        ]
        let signature = Self.signature(method: "POST", parameters: parameters, secret: accessKeySecret)
        let url = try URL.fixed("https://mt.cn-hangzhou.aliyuncs.com/")
        let fields = parameters + [("Signature", signature)]
        let (data, status) = try await http.dataWithStatus(.postForm(url, fields: fields))
        let response = try HTTPClient.decodeJSON(Response.self, data, status: status)
        if let text = response.Data?.Translated, response.Code?.value == "200" {
            return TranslationResult(text: text)
        }
        let code = response.Code?.value ?? "HTTP \(status)"
        throw TranslationError.service("阿里翻译错误 \(code)：\(response.Message ?? HTTPClient.snippet(data))")
    }

    /// 待签名串：`方法&%2F&编码(按参数名排序后的 k=v&k=v)`，密钥为 `AccessKeySecret&`。
    static func stringToSign(method: String, parameters: [(String, String)]) -> String {
        let canonical = parameters.sorted { $0.0 < $1.0 }
            .map { "\(FormEncoding.escape($0.0))=\(FormEncoding.escape($0.1))" }
            .joined(separator: "&")
        return "\(method)&\(FormEncoding.escape("/"))&\(FormEncoding.escape(canonical))"
    }

    static func signature(method: String, parameters: [(String, String)], secret: String) -> String {
        Crypto.hmacSHA1Base64(stringToSign(method: method, parameters: parameters), key: secret + "&")
    }

    static func code(_ language: Language) -> String? {
        switch language {
        case .auto: "auto"
        case .simplifiedChinese: "zh"
        case .traditionalChinese: "zh-tw"
        default: language.rawValue
        }
    }
}
