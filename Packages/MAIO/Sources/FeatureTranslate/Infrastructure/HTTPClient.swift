import Foundation

/// 翻译源共用的网络请求工具。只做三件事：发请求、检查状态码、把错误变成 `TranslationError`。
/// 会自动使用系统代理（Clash 等不用单独设置）。
struct HTTPClient: Sendable {
    static let timeout: TimeInterval = 15

    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// 发送请求，状态码不是 2xx 时抛出 `.http`（附带返回内容的前 300 个字符，方便看出原因）。
    func data(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        try Self.check(response, body: data)
        return data
    }

    /// 发送请求但不检查状态码：有些官方接口在 4xx 时也会返回带错误信息的 JSON，由调用方自己解析。
    func dataWithStatus(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 200)
    }

    /// 解析 JSON；失败时抛出 `.badResponse`（状态码不是 2xx 时抛出 `.http`）。
    static func decodeJSON<T: Decodable>(_: T.Type, _ data: Data, status: Int = 200) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            if !(200 ..< 300).contains(status) {
                throw TranslationError.http(status: status, body: snippet(data))
            }
            throw TranslationError.badResponse(snippet(data))
        }
    }

    func decode<T: Decodable>(_: T.Type, _ request: URLRequest) async throws -> T {
        let data = try await data(request)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw TranslationError.badResponse(Self.snippet(data))
        }
    }

    /// 逐行读取（大模型的 SSE 流式返回）。
    func lines(_ request: URLRequest) async throws -> AsyncLineSequence<URLSession.AsyncBytes> {
        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            var body = Data()
            for try await byte in bytes.prefix(2000) {
                body.append(byte)
            }
            throw TranslationError.http(status: http.statusCode, body: Self.snippet(body))
        }
        return bytes.lines
    }

    static func check(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw TranslationError.http(status: http.statusCode, body: snippet(body))
        }
    }

    static func snippet(_ data: Data) -> String {
        let text = String(bytes: data, encoding: .utf8) ?? "（\(data.count) 字节，无法按 UTF-8 显示）"
        return String(text.prefix(300))
    }
}

extension URLRequest {
    static func get(_ url: URL, headers: [String: String] = [:]) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: HTTPClient.timeout)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return request
    }

    /// JSON 请求体（`body` 用 Encodable 结构体，或 `[String: JSONBody]`）。
    static func postJSON(_ url: URL, body: some Encodable, headers: [String: String] = [:]) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: HTTPClient.timeout)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return request
    }

    /// 表单请求体（application/x-www-form-urlencoded）。
    static func postForm(_ url: URL, fields: [(String, String)], headers: [String: String] = [:]) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: HTTPClient.timeout)
        request.httpMethod = "POST"
        request.httpBody = Data(FormEncoding.encode(fields).utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return request
    }
}

enum FormEncoding {
    /// 按 RFC 3986 编码（空格编码为 %20，签名算法通常要求这种形式）。
    static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")

    static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    static func encode(_ fields: [(String, String)]) -> String {
        fields.map { "\(escape($0.0))=\(escape($0.1))" }.joined(separator: "&")
    }
}

extension URL {
    /// 由用户填写的地址构造 URL：补全 https://，去掉末尾的 /
    static func userProvided(_ string: String) throws -> URL {
        var value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") {
            value.removeLast()
        }
        if !value.contains("://") {
            value = "https://" + value
        }
        guard let url = URL(string: value), url.host() != nil else {
            throw TranslationError.service("地址格式不正确：\(string)")
        }
        return url
    }
}
