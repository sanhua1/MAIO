/// 一次翻译请求（发给单个翻译源）。
struct TranslationRequest: Sendable, Equatable {
    var text: String
    /// 源语言；`.auto` 表示交给翻译源自己识别
    var source: Language
    var target: Language
    /// 本地识别出的原文语言（`source` 为 `.auto` 时供必须指定源语言的翻译源使用，例如 Apple 翻译）
    var detected: Language?
}

/// 单个翻译源的结果。
struct TranslationResult: Sendable, Equatable, Codable {
    var text: String
    /// 查单词时的词典信息（只有部分翻译源提供）
    var dictionary: DictionaryEntry?

    init(text: String, dictionary: DictionaryEntry? = nil) {
        self.text = text
        self.dictionary = dictionary
    }
}

/// 词典模式：音标 + 按词性分组的释义。
struct DictionaryEntry: Sendable, Equatable, Codable {
    struct Meaning: Sendable, Equatable, Codable, Hashable {
        var partOfSpeech: String
        var terms: [String]
    }

    var phonetics: [String] = []
    var meanings: [Meaning] = []

    var isEmpty: Bool {
        phonetics.isEmpty && meanings.isEmpty
    }
}

/// 翻译源抛出的错误，信息直接显示在结果卡片上。
enum TranslationError: Error, Equatable, Sendable {
    case missingSecret(String)
    case unsupportedLanguage(Language)
    case http(status: Int, body: String)
    case badResponse(String)
    case service(String)

    var message: String {
        switch self {
        case let .missingSecret(field): "还没有填写 \(field)，请在设置 → 翻译 → 翻译源中填写"
        case let .unsupportedLanguage(language): "这个翻译源不支持\(language.displayName)"
        case let .http(status, body): "请求失败（HTTP \(status)）\(body.isEmpty ? "" : "：\(body)")"
        case let .badResponse(detail): "无法解析返回结果：\(detail)"
        case let .service(message): message
        }
    }
}

/// 翻译源。实现放在 Infrastructure/Providers/，每个源一个文件。
protocol TranslationProvider: Sendable {
    /// 翻译。支持逐字输出的源（大模型）每收到一段就调用 `onPartial`，参数是目前为止的完整译文。
    func translate(_ request: TranslationRequest, onPartial: @escaping @Sendable (String) -> Void) async throws
        -> TranslationResult
}
