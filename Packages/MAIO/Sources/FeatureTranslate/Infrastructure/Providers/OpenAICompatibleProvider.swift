import Foundation

// 参考：references/pot-desktop/src/services/translate/openai/index.jsx
/// 兼容 OpenAI Chat Completions 接口的大模型（DeepSeek、OpenAI、Gemini、智谱、Kimi、通义、硅基流动、Ollama…）。
/// 使用流式返回（SSE），译文逐字显示。
struct OpenAICompatibleProvider: TranslationProvider {
    let baseURL: String
    let model: String
    let apiKey: String?
    let prompt: PromptTemplate
    let http: HTTPClient

    private struct Body: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let messages: [Message]
        let stream = true
    }

    private struct Delta: Decodable {
        let content: String?
    }

    private struct Chunk: Decodable {
        struct Choice: Decodable {
            let delta: Delta?
            let message: Delta?
        }

        let choices: [Choice]?
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable {
            let message: String
        }

        let error: Detail
    }

    func translate(_ request: TranslationRequest, onPartial: @escaping @Sendable (String) -> Void) async throws
        -> TranslationResult {
        guard !model.isEmpty else { throw TranslationError.service("还没有填写模型名称") }
        let (system, user) = prompt.render(request)
        var headers = ["Accept": "text/event-stream"]
        if let apiKey, !apiKey.isEmpty {
            headers["Authorization"] = "Bearer \(apiKey)"
        }
        let body = Body(model: model, messages: [
            Body.Message(role: "system", content: system), Body.Message(role: "user", content: user),
        ])
        var urlRequest = try URLRequest.postJSON(Self.endpoint(baseURL), body: body, headers: headers)
        // 大模型首字可能较慢，放宽超时
        urlRequest.timeoutInterval = 60
        var text = ""
        var raw = ""
        for try await line in try await http.lines(urlRequest) {
            guard line.hasPrefix("data:") else {
                raw += line
                continue
            }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" {
                break
            }
            guard let piece = Self.content(of: payload) else { continue }
            text += piece
            onPartial(text)
        }
        if text.isEmpty {
            // 服务端没有按流式返回：按普通 JSON 解析
            text = try Self.nonStreaming(raw)
        }
        return TranslationResult(text: Self.stripQuotes(text))
    }

    /// 地址可以填到 /v1 为止，也可以填完整的 /chat/completions
    static func endpoint(_ base: String) throws -> URL {
        let url = try URL.userProvided(base)
        return url.path().hasSuffix("/chat/completions") ? url : url.appending(path: "chat/completions")
    }

    private static func content(of payload: String) -> String? {
        guard let chunk = try? JSONDecoder().decode(Chunk.self, from: Data(payload.utf8)) else { return nil }
        return chunk.choices?.first?.delta?.content
    }

    private static func nonStreaming(_ raw: String) throws -> String {
        let data = Data(raw.utf8)
        if let error = try? JSONDecoder().decode(ErrorBody.self, from: data) {
            throw TranslationError.service(error.error.message)
        }
        if let chunk = try? JSONDecoder().decode(Chunk.self, from: data),
           let content = chunk.choices?.first?.message?.content {
            return content
        }
        throw TranslationError.badResponse(String(raw.prefix(300)))
    }

    /// 有的模型会把译文包在提示词里的三引号中，去掉
    static func stripQuotes(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("\"\"\""), value.hasSuffix("\"\"\""), value.count >= 6 {
            value = String(value.dropFirst(3).dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }
}
