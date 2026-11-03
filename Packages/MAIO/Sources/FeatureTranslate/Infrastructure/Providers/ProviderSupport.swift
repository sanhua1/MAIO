import Foundation

/// 有的接口把错误码写成数字，有的写成字符串，统一解码成字符串。
struct LooseString: Decodable, Sendable, Equatable {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = String(int)
        } else {
            value = try container.decode(String.self)
        }
    }
}

/// 签名用的随机数与时间格式。
enum SigningClock {
    static func nonce() -> String {
        String(UInt32.random(in: 100_000 ... UInt32.max))
    }

    private static func utcFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter
    }

    /// 2019-02-25
    static func utcDay(_ date: Date) -> String {
        utcFormatter("yyyy-MM-dd").string(from: date)
    }

    /// 2016-02-23T12:46:24Z
    static func iso8601(_ date: Date) -> String {
        utcFormatter("yyyy-MM-dd'T'HH:mm:ss'Z'").string(from: date)
    }

    /// 20201230T081805Z
    static func compactISO8601(_ date: Date) -> String {
        utcFormatter("yyyyMMdd'T'HHmmss'Z'").string(from: date)
    }
}

extension TranslationRequest {
    /// 目标语言代码；不支持时抛出 `.unsupportedLanguage`。
    func targetCode(_ map: (Language) -> String?) throws -> String {
        guard target != .auto, let code = map(target) else { throw TranslationError.unsupportedLanguage(target) }
        return code
    }

    /// 源语言代码（`.auto` 映射成什么由各翻译源决定），不支持时抛错。
    func sourceCode(_ map: (Language) -> String?) throws -> String {
        guard let code = map(source) else { throw TranslationError.unsupportedLanguage(source) }
        return code
    }
}

extension URL {
    /// 代码里写死的地址。
    static func fixed(_ string: String) throws -> URL {
        guard let url = URL(string: string) else { throw TranslationError.service("地址无效：\(string)") }
        return url
    }
}
