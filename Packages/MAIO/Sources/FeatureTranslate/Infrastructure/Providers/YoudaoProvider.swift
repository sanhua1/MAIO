import Foundation

// 参考：references/pot-desktop/src/services/translate/youdao/index.jsx
/// 有道智云·文本翻译（签名 v3）。查单词时附带音标和释义。
struct YoudaoProvider: TranslationProvider {
    let appKey: String
    let appSecret: String
    let http: HTTPClient

    /// 词典信息（只有查单词时返回）
    private struct Basic: Decodable {
        let phonetic: String?
        let explains: [String]?
        let ukPhonetic: String?
        let usPhonetic: String?

        private enum CodingKeys: String, CodingKey {
            case phonetic, explains
            case ukPhonetic = "uk-phonetic"
            case usPhonetic = "us-phonetic"
        }
    }

    private struct Response: Decodable {
        let errorCode: LooseString?
        let translation: [String]?
        let basic: Basic?
    }

    func translate(_ request: TranslationRequest, onPartial _: @escaping @Sendable (String) -> Void) async throws
        -> TranslationResult {
        let target = try request.targetCode(Self.code)
        let source = try request.sourceCode(Self.code)
        let salt = UUID().uuidString.lowercased()
        let curtime = String(Int(Date().timeIntervalSince1970))
        let sign = Self.sign(appKey: appKey, text: request.text, salt: salt, curtime: curtime, appSecret: appSecret)
        let fields = [
            ("q", request.text), ("from", source), ("to", target), ("appKey", appKey), ("salt", salt),
            ("sign", sign), ("signType", "v3"), ("curtime", curtime),
        ]
        let url = try URL.fixed("https://openapi.youdao.com/api")
        let (data, status) = try await http.dataWithStatus(.postForm(url, fields: fields))
        let response = try HTTPClient.decodeJSON(Response.self, data, status: status)
        if let code = response.errorCode, code.value != "0" {
            throw TranslationError.service("有道翻译错误 \(code.value)：\(Self.describe(code.value))")
        }
        guard let lines = response.translation else { throw TranslationError.badResponse(HTTPClient.snippet(data)) }
        return TranslationResult(text: lines.joined(separator: "\n"), dictionary: Self.dictionary(response.basic))
    }

    private static func dictionary(_ basic: Basic?) -> DictionaryEntry? {
        guard let basic else { return nil }
        var entry = DictionaryEntry()
        if let uk = basic.ukPhonetic, !uk.isEmpty {
            entry.phonetics.append("英 /\(uk)/")
        }
        if let us = basic.usPhonetic, !us.isEmpty {
            entry.phonetics.append("美 /\(us)/")
        }
        if entry.phonetics.isEmpty, let phonetic = basic.phonetic, !phonetic.isEmpty {
            entry.phonetics.append("/\(phonetic)/")
        }
        for line in basic.explains ?? [] {
            // 形如 "n. 苹果；苹果树"：第一个以 . 结尾的词是词性
            let head = line.split(separator: " ", maxSplits: 1).map(String.init)
            let hasPOS = head.count == 2 && head[0].hasSuffix(".")
            let body = hasPOS ? head[1] : line
            let terms = body.split(separator: "；").map { $0.trimmingCharacters(in: .whitespaces) }
            entry.meanings.append(.init(partOfSpeech: hasPOS ? head[0] : "", terms: terms))
        }
        return entry.isEmpty ? nil : entry
    }

    /// v3 签名：sha256(应用ID + input + salt + curtime + 应用密钥)。
    static func sign(appKey: String, text: String, salt: String, curtime: String, appSecret: String) -> String {
        Crypto.sha256Hex(appKey + truncate(text) + salt + curtime + appSecret)
    }

    /// input 规则：长度 ≤ 20 时取原文，否则取「前 10 个字符 + 长度 + 后 10 个字符」。
    /// 按 Unicode 标量计数（与官方 Python 示例 `len(q)` 一致）。
    static func truncate(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count > 20 else { return text }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars.prefix(10))
        let head = String(view)
        view = String.UnicodeScalarView()
        view.append(contentsOf: scalars.suffix(10))
        return head + String(scalars.count) + String(view)
    }

    private static func describe(_ code: String) -> String {
        switch code {
        case "101": "缺少必填参数"
        case "102": "不支持的语言类型"
        case "108": "应用 ID 无效"
        case "110": "应用没有绑定文本翻译服务"
        case "202": "签名校验失败，请检查应用 ID 和应用密钥"
        case "206": "时间戳无效，请检查系统时间"
        case "401": "账户已欠费"
        case "411": "访问频率受限"
        default: "请对照有道智云文档查看错误码含义"
        }
    }

    static func code(_ language: Language) -> String? {
        switch language {
        case .auto: "auto"
        case .simplifiedChinese: "zh-CHS"
        case .traditionalChinese: "zh-CHT"
        default: language.rawValue
        }
    }
}
