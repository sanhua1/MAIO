/// 每种翻译源的说明与配置项（设置界面据此自动生成表单）。
extension ProviderKind {
    var spec: ProviderSpec {
        switch self {
        case .google, .bing, .transmart, .apple: freeSpec
        case .openAICompatible: Self.openAISpec
        default: keyedSpec
        }
    }

    private var freeSpec: ProviderSpec {
        switch self {
        case .google:
            ProviderSpec(
                displayName: "Google 翻译", symbol: "g.circle", cost: .free,
                summary: "免费，质量好，查单词时显示音标和释义。国内需要代理。",
                fields: [ProviderField(
                    key: "baseURL", title: "服务地址", placeholder: "https://translate.googleapis.com",
                    defaultValue: "https://translate.googleapis.com", isRequired: false,
                )],
            )
        case .bing:
            ProviderSpec(
                displayName: "必应翻译", symbol: "b.circle", cost: .free,
                summary: "免费，国内可直连。使用必应网页翻译器的接口。",
            )
        case .transmart:
            ProviderSpec(
                displayName: "腾讯交互翻译", symbol: "t.circle", cost: .free,
                summary: "免费，国内可直连（transmart.qq.com）。",
            )
        default:
            ProviderSpec(
                displayName: "Apple 翻译", symbol: "apple.logo", cost: .offline,
                summary: "系统自带，离线可用。需要先在「系统设置 → 通用 → 语言与地区 → 翻译语言」下载语言包。",
            )
        }
    }

    static let openAISpec = ProviderSpec(
        displayName: "大模型（OpenAI 兼容）", symbol: "sparkles", cost: .paid,
        summary: "DeepSeek、OpenAI、Gemini、智谱、Kimi、通义、硅基流动、Ollama 等兼容 OpenAI 接口的服务。译文逐字显示。",
        fields: [
            ProviderField(key: "baseURL", title: "接口地址", placeholder: "https://api.deepseek.com"),
            ProviderField(key: "model", title: "模型", placeholder: "deepseek-chat"),
            ProviderField(key: "apiKey", title: "API Key", kind: .secret, isRequired: false),
            ProviderField(
                key: "systemPrompt", title: "系统提示词", kind: .multiline,
                defaultValue: PromptTemplate.default.system, isRequired: false,
            ),
            ProviderField(
                key: "userPrompt", title: "用户提示词", kind: .multiline,
                defaultValue: PromptTemplate.default.user, isRequired: false,
            ),
        ],
        allowsMultiple: true,
    )

    private var keyedSpec: ProviderSpec {
        switch self {
        case .deepl:
            ProviderSpec(
                displayName: "DeepL", symbol: "d.circle", cost: .freeQuota,
                summary: "免费版 API 每月 50 万字符。Key 以 :fx 结尾时自动使用免费版地址。也可以填 DeepLX 地址。",
                signupURL: "https://www.deepl.com/pro-api",
                fields: [
                    ProviderField(key: "authKey", title: "Auth Key", kind: .secret, isRequired: false),
                    ProviderField(
                        key: "customURL", title: "自定义地址（DeepLX）", placeholder: "留空使用官方 API",
                        isRequired: false,
                    ),
                ],
            )
        case .baidu:
            ProviderSpec(
                displayName: "百度翻译", symbol: "b.square", cost: .freeQuota,
                summary: "通用文本翻译，认证后每月有免费额度。",
                signupURL: "https://fanyi-api.baidu.com/manage/developer",
                fields: [
                    ProviderField(key: "appID", title: "APP ID"),
                    ProviderField(key: "secret", title: "密钥", kind: .secret),
                ],
            )
        case .youdao:
            ProviderSpec(
                displayName: "有道翻译", symbol: "y.circle", cost: .freeQuota,
                summary: "有道智云文本翻译，新用户有体验额度。",
                signupURL: "https://ai.youdao.com/console/",
                fields: [
                    ProviderField(key: "appKey", title: "应用 ID"),
                    ProviderField(key: "appSecret", title: "应用密钥", kind: .secret),
                ],
            )
        case .tencent:
            ProviderSpec(
                displayName: "腾讯云翻译", symbol: "t.square", cost: .freeQuota,
                summary: "腾讯云机器翻译，每月有免费额度。",
                signupURL: "https://console.cloud.tencent.com/cam/capi",
                fields: [
                    ProviderField(key: "secretID", title: "SecretId"),
                    ProviderField(key: "secretKey", title: "SecretKey", kind: .secret),
                    ProviderField(key: "region", title: "地域", defaultValue: "ap-beijing", isRequired: false),
                ],
            )
        default:
            otherKeyedSpec
        }
    }

    private var otherKeyedSpec: ProviderSpec {
        switch self {
        case .alibaba:
            ProviderSpec(
                displayName: "阿里翻译", symbol: "a.circle", cost: .freeQuota,
                summary: "阿里云机器翻译（通用版），每月有免费额度。",
                signupURL: "https://ram.console.aliyun.com/manage/ak",
                fields: [
                    ProviderField(key: "accessKeyID", title: "AccessKey ID"),
                    ProviderField(key: "accessKeySecret", title: "AccessKey Secret", kind: .secret),
                ],
            )
        case .volcengine:
            ProviderSpec(
                displayName: "火山翻译", symbol: "v.circle", cost: .freeQuota,
                summary: "火山引擎机器翻译，每月有免费额度。",
                signupURL: "https://console.volcengine.com/iam/keymanage/",
                fields: [
                    ProviderField(key: "accessKeyID", title: "Access Key ID"),
                    ProviderField(key: "secretAccessKey", title: "Secret Access Key", kind: .secret),
                ],
            )
        case .caiyun:
            ProviderSpec(
                displayName: "彩云小译", symbol: "c.circle", cost: .freeQuota,
                summary: "彩云小译 API，新用户有免费额度。",
                signupURL: "https://dashboard.caiyunapp.com/",
                fields: [ProviderField(key: "token", title: "Token", kind: .secret)],
            )
        default:
            ProviderSpec(
                displayName: "小牛翻译", symbol: "n.circle", cost: .freeQuota,
                summary: "小牛翻译开放平台，每天有免费额度。",
                signupURL: "https://niutrans.com/cloud/account_info/info",
                fields: [ProviderField(key: "apiKey", title: "API Key", kind: .secret)],
            )
        }
    }
}
