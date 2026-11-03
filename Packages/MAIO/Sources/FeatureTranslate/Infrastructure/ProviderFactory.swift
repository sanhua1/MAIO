import Foundation
import MAIOKit

/// 根据配置创建翻译源。持有需要跨次复用的状态（必应的网页凭证）。
@MainActor
final class ProviderFactory {
    private let http = HTTPClient()
    private let bing = BingSession()
    private let secrets: any SecretService

    init(secrets: any SecretService) {
        self.secrets = secrets
    }

    /// 预热需要会话的翻译源（目前只有必应）
    func prewarm(_ services: [ServiceConfig]) {
        guard services.contains(where: { $0.kind == .bing && $0.isEnabled }) else { return }
        let bing = bing
        Task { await bing.prewarm() }
    }

    func make(_ config: ServiceConfig) -> any TranslationProvider {
        do {
            return try build(config)
        } catch {
            return FailingProvider(error: error)
        }
    }

    private func build(_ config: ServiceConfig) throws -> any TranslationProvider {
        switch config.kind {
        case .google:
            return GoogleProvider(baseURL: config.option("baseURL"), http: http)
        case .bing:
            return BingProvider(session: bing)
        case .transmart:
            return TransmartProvider(http: http)
        case .apple:
            return AppleProvider()
        case .openAICompatible:
            let prompt = PromptTemplate(system: config.option("systemPrompt"), user: config.option("userPrompt"))
            return OpenAICompatibleProvider(
                baseURL: config.option("baseURL"), model: config.option("model"),
                apiKey: secrets.secret(for: config.secretKey("apiKey")), prompt: prompt, http: http,
            )
        default:
            let values = try resolvedValues(config)
            return try KeyedProviders.make(config.kind, values: values, http: http)
        }
    }

    /// 合并普通配置和钥匙串中的密钥；必填项缺失时抛错（显示在结果卡片上）。
    private func resolvedValues(_ config: ServiceConfig) throws -> [String: String] {
        var values: [String: String] = [:]
        for field in config.spec.fields {
            let value = field.kind == .secret
                ? secrets.secret(for: config.secretKey(field.key)) ?? ""
                : config.option(field.key)
            if field.isRequired, value.isEmpty {
                throw TranslationError.missingSecret(field.title)
            }
            values[field.key] = value
        }
        return values
    }
}

/// 配置不完整时使用：翻译时直接报告原因。
struct FailingProvider: TranslationProvider {
    let error: any Error

    func translate(_: TranslationRequest, onPartial _: @escaping @Sendable (String) -> Void) async throws
        -> TranslationResult {
        throw error
    }
}
