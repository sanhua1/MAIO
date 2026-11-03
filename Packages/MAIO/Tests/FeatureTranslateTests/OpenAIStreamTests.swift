@testable import FeatureTranslate
import Foundation
import Synchronization
import Testing

/// 用假的 URLProtocol 模拟大模型服务端，验证流式 / 非流式 / 错误三种返回的解析。
@Suite(.serialized)
struct OpenAIStreamTests {
    private func provider() -> OpenAICompatibleProvider {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return OpenAICompatibleProvider(
            baseURL: "https://llm.test/v1", model: "test-model", apiKey: "sk-test",
            prompt: .default, http: HTTPClient(session: URLSession(configuration: configuration)),
        )
    }

    private let request = TranslationRequest(text: "hello", source: .english, target: .simplifiedChinese)

    @Test func `streams partial text`() async throws {
        StubProtocol.respond(status: 200, body: """
        data: {"choices":[{"delta":{"role":"assistant","content":""}}]}

        data: {"choices":[{"delta":{"content":"你"}}]}

        data: {"choices":[{"delta":{"content":"好"}}]}

        data: [DONE]

        """)
        let partials = Mutex<[String]>([])
        let result = try await provider().translate(request) { text in partials.withLock { $0.append(text) } }
        #expect(result.text == "你好")
        #expect(partials.withLock { $0 } == ["", "你", "你好"])
        let sent = try #require(StubProtocol.lastRequest)
        #expect(sent.url?.absoluteString == "https://llm.test/v1/chat/completions")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
    }

    @Test func `accepts non streaming response`() async throws {
        StubProtocol.respond(status: 200, body: #"{"choices":[{"message":{"content":"你好"}}]}"#)
        let result = try await provider().translate(request) { _ in }
        #expect(result.text == "你好")
    }

    @Test func `surfaces HTTP error`() async {
        StubProtocol.respond(status: 401, body: #"{"error":{"message":"Authentication Fails"}}"#)
        await #expect {
            try await provider().translate(request) { _ in }
        } throws: { error in
            guard case let .http(status, body) = error as? TranslationError else { return false }
            return status == 401 && body.contains("Authentication Fails")
        }
    }
}

final class StubProtocol: URLProtocol {
    private struct Stub {
        var status = 200
        var body = Data()
        var lastRequest: URLRequest?
    }

    private static let stub = Mutex(Stub())

    static func respond(status: Int, body: String) {
        stub.withLock { $0 = Stub(status: status, body: Data(body.utf8)) }
    }

    static var lastRequest: URLRequest? {
        stub.withLock { $0.lastRequest }
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let current = Self.stub.withLock { stub in
            stub.lastRequest = request
            return stub
        }
        let url = request.url ?? URL(fileURLWithPath: "/")
        let response = HTTPURLResponse(url: url, statusCode: current.status, httpVersion: nil, headerFields: nil)
        if let response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: current.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
