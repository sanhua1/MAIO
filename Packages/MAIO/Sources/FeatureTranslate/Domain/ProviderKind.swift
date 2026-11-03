/// 翻译源类型。新增一个源：在这里加一个 case 和 spec，在 Infrastructure/Providers/ 加实现，在 ProviderFactory 注册。
enum ProviderKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case google
    case bing
    case transmart
    case apple
    case openAICompatible
    case deepl
    case baidu
    case youdao
    case tencent
    case alibaba
    case volcengine
    case caiyun
    case niutrans

    var id: String {
        rawValue
    }
}

/// 翻译源的一个配置项。
struct ProviderField: Sendable, Hashable, Identifiable {
    enum Kind: Sendable, Hashable {
        case text
        /// 存进钥匙串（ADR-0009），不写进设置文件
        case secret
        case multiline
    }

    let key: String
    let title: String
    var kind: Kind = .text
    var placeholder = ""
    var defaultValue = ""
    var isRequired = true

    var id: String {
        key
    }
}

/// 翻译源的静态说明：名称、费用、配置项。
struct ProviderSpec: Sendable {
    enum Cost: Sendable {
        /// 免费、不需要 Key（非官方接口，可能失效）
        case free
        /// 免费、离线
        case offline
        /// 需要 Key，有免费额度
        case freeQuota
        /// 需要 Key，按量付费
        case paid
    }

    let displayName: String
    let symbol: String
    let cost: Cost
    let summary: String
    /// 申请 Key 的地址
    var signupURL: String?
    var fields: [ProviderField] = []
    /// 能否同时存在多个实例（例如多个大模型服务）
    var allowsMultiple = false
}
