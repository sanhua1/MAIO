import Foundation

/// 需要 API Key 的官方翻译接口。`values` 已包含该源全部配置项（含密钥，必填项已校验非空）。
enum KeyedProviders {
    static func make(_ kind: ProviderKind, values: [String: String], http: HTTPClient) throws
        -> any TranslationProvider {
        let value = { (key: String) in values[key, default: ""].trimmingCharacters(in: .whitespacesAndNewlines) }
        switch kind {
        case .deepl:
            return DeepLProvider(authKey: value("authKey"), customURL: value("customURL"), http: http)
        case .baidu:
            return BaiduProvider(appID: value("appID"), secret: value("secret"), http: http)
        case .youdao:
            return YoudaoProvider(appKey: value("appKey"), appSecret: value("appSecret"), http: http)
        case .tencent:
            return TencentProvider(
                secretID: value("secretID"), secretKey: value("secretKey"), region: value("region"), http: http,
            )
        case .alibaba:
            return AlibabaProvider(accessKeyID: value("accessKeyID"), accessKeySecret: value("accessKeySecret"), http: http)
        case .volcengine:
            return VolcengineProvider(
                accessKeyID: value("accessKeyID"), secretAccessKey: value("secretAccessKey"), http: http,
            )
        case .caiyun:
            return CaiyunProvider(token: value("token"), http: http)
        case .niutrans:
            return NiutransProvider(apiKey: value("apiKey"), http: http)
        case .google, .bing, .transmart, .apple, .openAICompatible:
            throw TranslationError.service("\(kind.spec.displayName) 不是需要 API Key 的翻译源")
        }
    }
}
