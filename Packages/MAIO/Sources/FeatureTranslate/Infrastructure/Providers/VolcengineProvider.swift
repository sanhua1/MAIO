import Foundation

// 参考：references/pot-desktop/src/services/translate/volcengine/index.jsx
// 签名步骤对照官方文档：https://www.volcengine.com/docs/6369/67269
/// 火山引擎机器翻译 TranslateText（OpenAPI 签名 HMAC-SHA256，与 AWS SigV4 同构）。
struct VolcengineProvider: TranslationProvider {
    let accessKeyID: String
    let secretAccessKey: String
    let http: HTTPClient

    static let host = "translate.volcengineapi.com"
    static let query = "Action=TranslateText&Version=2020-06-01"

    private struct Body: Encodable {
        let SourceLanguage: String?
        let TargetLanguage: String
        let TextList: [String]
    }

    private struct Failure: Decodable {
        let Code: String?
        let Message: String?
    }

    private struct Response: Decodable {
        struct Item: Decodable {
            let Translation: String
        }

        struct Metadata: Decodable {
            let Error: Failure?
        }

        let TranslationList: [Item]?
        let ResponseMetadata: Metadata?
    }

    func translate(_ request: TranslationRequest, onPartial _: @escaping @Sendable (String) -> Void) async throws
        -> TranslationResult {
        let target = try request.targetCode(Self.code)
        let source = request.source == .auto ? nil : try request.sourceCode(Self.code)
        let payload = try JSONEncoder().encode(Body(SourceLanguage: source, TargetLanguage: target, TextList: [request.text]))
        let signing = VolcengineSigning(host: Self.host, query: Self.query, payload: payload, date: Date())
        var urlRequest = try URLRequest(
            url: URL.fixed("https://\(Self.host)/?\(Self.query)"),
            timeoutInterval: HTTPClient.timeout,
        )
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = payload
        let headers = [
            "Authorization": signing.authorization(accessKeyID: accessKeyID, secret: secretAccessKey),
            "Content-Type": VolcengineSigning.contentType, "X-Date": signing.timestamp,
            "X-Content-Sha256": Crypto.sha256Hex(payload),
        ]
        headers.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }
        let (data, status) = try await http.dataWithStatus(urlRequest)
        let response = try HTTPClient.decodeJSON(Response.self, data, status: status)
        if let error = response.ResponseMetadata?.Error {
            throw TranslationError.service("火山翻译错误 \(error.Code ?? "")：\(error.Message ?? "未知错误")")
        }
        guard let items = response.TranslationList else { throw TranslationError.badResponse(HTTPClient.snippet(data)) }
        return TranslationResult(text: items.map(\.Translation).joined(separator: "\n"))
    }

    static func code(_ language: Language) -> String? {
        switch language {
        case .auto: "auto"
        case .simplifiedChinese: "zh"
        case .traditionalChinese: "zh-Hant"
        default: language.rawValue
        }
    }
}

/// 火山引擎 OpenAPI 签名。签名头：content-type;host;x-content-sha256;x-date。
struct VolcengineSigning {
    let host: String
    /// 已按参数名排序、编码好的查询串
    let query: String
    let payload: Data
    let date: Date
    var region = "cn-north-1"
    var service = "translate"

    static let contentType = "application/json"
    static let signedHeaders = "content-type;host;x-content-sha256;x-date"

    /// X-Date，例如 20201230T081805Z
    var timestamp: String {
        SigningClock.compactISO8601(date)
    }

    var credentialScope: String {
        "\(timestamp.prefix(8))/\(region)/\(service)/request"
    }

    var canonicalRequest: String {
        let bodyHash = Crypto.sha256Hex(payload)
        let headers = "content-type:\(Self.contentType)\nhost:\(host)\nx-content-sha256:\(bodyHash)\nx-date:\(timestamp)\n"
        return ["POST", "/", query, headers, Self.signedHeaders, bodyHash].joined(separator: "\n")
    }

    var stringToSign: String {
        ["HMAC-SHA256", timestamp, credentialScope, Crypto.sha256Hex(canonicalRequest)].joined(separator: "\n")
    }

    func signature(secret: String) -> String {
        let kDate = Crypto.hmacSHA256(String(timestamp.prefix(8)), key: Data(secret.utf8))
        let kRegion = Crypto.hmacSHA256(region, key: kDate)
        let kService = Crypto.hmacSHA256(service, key: kRegion)
        let kSigning = Crypto.hmacSHA256("request", key: kService)
        return Crypto.hmacSHA256Hex(stringToSign, key: kSigning)
    }

    func authorization(accessKeyID: String, secret: String) -> String {
        "HMAC-SHA256 Credential=\(accessKeyID)/\(credentialScope), SignedHeaders=\(Self.signedHeaders), "
            + "Signature=\(signature(secret: secret))"
    }
}
