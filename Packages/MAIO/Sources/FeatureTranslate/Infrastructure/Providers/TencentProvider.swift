import Foundation

// 参考：references/pot-desktop/src/services/translate/tencent/index.jsx
// 签名步骤对照官方文档：https://cloud.tencent.com/document/api/551/30636
/// 腾讯云机器翻译 TextTranslate（API 3.0，签名 TC3-HMAC-SHA256）。
struct TencentProvider: TranslationProvider {
    let secretID: String
    let secretKey: String
    let region: String
    let http: HTTPClient

    static let host = "tmt.tencentcloudapi.com"
    static let contentType = "application/json; charset=utf-8"

    private struct Body: Encodable {
        let SourceText: String
        let Source: String
        let Target: String
        let ProjectId = 0
    }

    private struct Failure: Decodable {
        let Code: String
        let Message: String
    }

    private struct Envelope: Decodable {
        struct Inner: Decodable {
            let TargetText: String?
            let Error: Failure?
        }

        let Response: Inner
    }

    func translate(_ request: TranslationRequest, onPartial _: @escaping @Sendable (String) -> Void) async throws
        -> TranslationResult {
        let target = try request.targetCode(Self.code)
        let source = try request.sourceCode(Self.code)
        let payload = try JSONEncoder().encode(Body(SourceText: request.text, Source: source, Target: target))
        let timestamp = Int(Date().timeIntervalSince1970)
        let signing = TencentSigning(
            host: Self.host, service: "tmt", action: "TextTranslate", contentType: Self.contentType,
            payload: payload, timestamp: timestamp,
        )
        var urlRequest = try URLRequest(url: URL.fixed("https://\(Self.host)"), timeoutInterval: HTTPClient.timeout)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = payload
        let headers = [
            "Authorization": signing.authorization(secretID: secretID, secretKey: secretKey),
            "Content-Type": Self.contentType, "X-TC-Action": "TextTranslate", "X-TC-Version": "2018-03-21",
            "X-TC-Timestamp": String(timestamp), "X-TC-Region": region.isEmpty ? "ap-beijing" : region,
        ]
        headers.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }
        let (data, status) = try await http.dataWithStatus(urlRequest)
        let response = try HTTPClient.decodeJSON(Envelope.self, data, status: status).Response
        if let error = response.Error {
            throw TranslationError.service("腾讯云翻译错误 \(error.Code)：\(error.Message)")
        }
        guard let text = response.TargetText else { throw TranslationError.badResponse(HTTPClient.snippet(data)) }
        return TranslationResult(text: text)
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

/// TC3-HMAC-SHA256 签名。签名头：content-type;host;x-tc-action（与官方文档示例一致）。
struct TencentSigning {
    let host: String
    let service: String
    let action: String
    let contentType: String
    let payload: Data
    /// Unix 秒
    let timestamp: Int

    static let algorithm = "TC3-HMAC-SHA256"
    static let signedHeaders = "content-type;host;x-tc-action"

    var date: String {
        SigningClock.utcDay(Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    var credentialScope: String {
        "\(date)/\(service)/tc3_request"
    }

    var canonicalRequest: String {
        [
            "POST", "/", "",
            "content-type:\(contentType)\nhost:\(host)\nx-tc-action:\(action.lowercased())\n",
            Self.signedHeaders, Crypto.sha256Hex(payload),
        ].joined(separator: "\n")
    }

    var stringToSign: String {
        [Self.algorithm, String(timestamp), credentialScope, Crypto.sha256Hex(canonicalRequest)]
            .joined(separator: "\n")
    }

    func signature(secretKey: String) -> String {
        let secretDate = Crypto.hmacSHA256(date, key: Data("TC3\(secretKey)".utf8))
        let secretService = Crypto.hmacSHA256(service, key: secretDate)
        let secretSigning = Crypto.hmacSHA256("tc3_request", key: secretService)
        return Crypto.hmacSHA256Hex(stringToSign, key: secretSigning)
    }

    func authorization(secretID: String, secretKey: String) -> String {
        "\(Self.algorithm) Credential=\(secretID)/\(credentialScope), SignedHeaders=\(Self.signedHeaders), "
            + "Signature=\(signature(secretKey: secretKey))"
    }
}
