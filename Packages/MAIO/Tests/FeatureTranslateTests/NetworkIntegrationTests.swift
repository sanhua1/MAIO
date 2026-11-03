@testable import FeatureTranslate
import Foundation
import Testing

/// 真实联网测试，默认跳过。运行：MAIO_NETWORK_TESTS=1 swift test --filter NetworkIntegration
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MAIO_NETWORK_TESTS"] == "1"))
struct NetworkIntegrationTests {
    private let request = TranslationRequest(
        text: "Good morning, how are you?", source: .auto, target: .simplifiedChinese, detected: .english,
    )

    @Test func google() async throws {
        let result = try await GoogleProvider(baseURL: "https://translate.googleapis.com", http: HTTPClient())
            .translate(request) { _ in }
        #expect(result.text.contains("早"))
    }

    @Test func `google word`() async throws {
        let word = TranslationRequest(text: "apple", source: .auto, target: .simplifiedChinese)
        let result = try await GoogleProvider(baseURL: "https://translate.googleapis.com", http: HTTPClient())
            .translate(word) { _ in }
        #expect(result.dictionary?.meanings.isEmpty == false)
    }

    @Test func bing() async throws {
        let session = BingSession()
        let result = try await BingProvider(session: session).translate(request) { _ in }
        #expect(result.text.contains("早"))
        // 第二次复用缓存的凭证
        let again = try await BingProvider(session: session).translate(request) { _ in }
        #expect(again.text == result.text)
    }

    @Test func transmart() async throws {
        let result = try await TransmartProvider(http: HTTPClient()).translate(request) { _ in }
        #expect(result.text.contains("早"))
    }

    @Test func apple() async throws {
        do {
            let result = try await AppleProvider().translate(request) { _ in }
            #expect(!result.text.isEmpty)
        } catch let error as TranslationError {
            // 没下载语言包时应给出明确提示
            #expect(error.message.contains("语言包"))
        }
    }
}
