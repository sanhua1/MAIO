import Foundation

// 参考：references/pot-desktop/src/services/translate/google/index.jsx
/// Google 翻译（网页版 gtx 接口，免费、无需 Key）。查单词时返回音标和按词性分组的释义。
struct GoogleProvider: TranslationProvider {
    let baseURL: String
    let http: HTTPClient

    func translate(_ request: TranslationRequest, onPartial _: @escaping @Sendable (String) -> Void) async throws
        -> TranslationResult {
        guard let target = Self.code(request.target) else { throw TranslationError.unsupportedLanguage(request.target) }
        let source = Self.code(request.source) ?? "auto"
        var components = try URLComponents(url: URL.userProvided(baseURL), resolvingAgainstBaseURL: false)
        components?.path = "/translate_a/single"
        components?.queryItems = [
            URLQueryItem(name: "client", value: "gtx"), URLQueryItem(name: "sl", value: source),
            URLQueryItem(name: "tl", value: target), URLQueryItem(name: "hl", value: target),
            URLQueryItem(name: "dt", value: "t"), URLQueryItem(name: "dt", value: "bd"),
            URLQueryItem(name: "dt", value: "rm"), URLQueryItem(name: "ie", value: "UTF-8"),
            URLQueryItem(name: "oe", value: "UTF-8"), URLQueryItem(name: "q", value: request.text),
        ]
        guard let url = components?.url else { throw TranslationError.service("地址格式不正确：\(baseURL)") }
        let data = try await http.data(.get(url))
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> TranslationResult {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = root.first as? [Any]
        else {
            throw TranslationError.badResponse(HTTPClient.snippet(data))
        }
        var text = ""
        var phonetics: [String] = []
        for case let segment as [Any] in segments {
            if let piece = segment.first as? String {
                text += piece
            } else if segment.count > 3, let phonetic = segment[3] as? String, !phonetic.isEmpty {
                phonetics.append("/\(phonetic)/")
            }
        }
        var entry = DictionaryEntry(phonetics: phonetics)
        if root.count > 1, let groups = root[1] as? [Any] {
            for case let group as [Any] in groups {
                guard let pos = group.first as? String, group.count > 1, let terms = group[1] as? [String] else { continue }
                entry.meanings.append(.init(partOfSpeech: pos, terms: Array(terms.prefix(8))))
            }
        }
        return TranslationResult(text: text, dictionary: entry.meanings.isEmpty ? nil : entry)
    }

    static func code(_ language: Language) -> String? {
        switch language {
        case .auto: "auto"
        case .simplifiedChinese: "zh-CN"
        case .traditionalChinese: "zh-TW"
        default: language.rawValue
        }
    }
}
