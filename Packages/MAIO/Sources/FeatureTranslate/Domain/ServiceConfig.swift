import Foundation

/// 一个翻译源实例（同一种源可以有多个，例如多个大模型服务）。
/// 非敏感配置存在 `options`；密钥存在钥匙串，键为 `<id>.<字段 key>`。
struct ServiceConfig: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var kind: ProviderKind
    var name: String
    var isEnabled: Bool
    var options: [String: String] = [:]

    var spec: ProviderSpec {
        kind.spec
    }

    /// 取配置值，没填时用默认值
    func option(_ key: String) -> String {
        let value = options[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !value.isEmpty {
            return value
        }
        return spec.fields.first { $0.key == key }?.defaultValue ?? ""
    }

    func secretKey(_ field: String) -> String {
        "\(id).\(field)"
    }

    static func make(kind: ProviderKind, id: String, isEnabled: Bool = true) -> ServiceConfig {
        ServiceConfig(id: id, kind: kind, name: kind.spec.displayName, isEnabled: isEnabled)
    }

    /// 出厂配置：三个免费源默认启用；Apple 翻译需要下载语言包，DeepSeek 需要 Key，默认关闭。
    static let defaults: [ServiceConfig] = [
        .make(kind: .google, id: "google"),
        .make(kind: .bing, id: "bing"),
        .make(kind: .transmart, id: "transmart"),
        .make(kind: .apple, id: "apple", isEnabled: false),
        LLMPreset.deepSeek.makeConfig(id: "deepseek", isEnabled: false),
    ]
}

/// 大模型服务预设：只是帮用户填好地址和模型，之后可以随意修改。
struct LLMPreset: Sendable, Identifiable, Hashable {
    let name: String
    let baseURL: String
    let model: String
    let signupURL: String

    var id: String {
        name
    }

    func makeConfig(id: String, isEnabled: Bool = true) -> ServiceConfig {
        ServiceConfig(
            id: id, kind: .openAICompatible, name: name, isEnabled: isEnabled,
            options: ["baseURL": baseURL, "model": model],
        )
    }

    static let deepSeek = LLMPreset(
        name: "DeepSeek", baseURL: "https://api.deepseek.com", model: "deepseek-chat",
        signupURL: "https://platform.deepseek.com/api_keys",
    )

    static let all: [LLMPreset] = [
        deepSeek,
        LLMPreset(
            name: "OpenAI", baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini",
            signupURL: "https://platform.openai.com/api-keys",
        ),
        LLMPreset(
            name: "Gemini", baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
            model: "gemini-2.5-flash", signupURL: "https://aistudio.google.com/apikey",
        ),
        LLMPreset(
            name: "智谱 GLM", baseURL: "https://open.bigmodel.cn/api/paas/v4", model: "glm-4-flash",
            signupURL: "https://open.bigmodel.cn/usercenter/apikeys",
        ),
        LLMPreset(
            name: "Kimi", baseURL: "https://api.moonshot.cn/v1", model: "moonshot-v1-8k",
            signupURL: "https://platform.moonshot.cn/console/api-keys",
        ),
        LLMPreset(
            name: "通义千问", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-plus",
            signupURL: "https://bailian.console.aliyun.com/?apiKey=1",
        ),
        LLMPreset(
            name: "硅基流动", baseURL: "https://api.siliconflow.cn/v1", model: "Qwen/Qwen2.5-7B-Instruct",
            signupURL: "https://cloud.siliconflow.cn/account/ak",
        ),
        LLMPreset(
            name: "Ollama（本机）", baseURL: "http://localhost:11434/v1", model: "qwen2.5",
            signupURL: "https://ollama.com/download",
        ),
    ]
}
