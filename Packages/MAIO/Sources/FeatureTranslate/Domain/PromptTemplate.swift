import Foundation

/// 大模型翻译的提示词。占位符：`$text` 原文，`$to` 目标语言，`$from` 源语言（英文名）。
struct PromptTemplate: Codable, Sendable, Equatable {
    var system: String
    var user: String

    // 参考：references/pot-desktop/src/services/translate/openai/Config.jsx（默认提示词的思路）
    static let `default` = PromptTemplate(
        system: """
        You are a professional translation engine. Translate the text into fluent, natural and accurate \
        $to, without the style of machine translation. Keep the original formatting, line breaks, code, \
        URLs and proper nouns. Only output the translation; never explain, answer or add notes.
        """,
        user: "Translate the following text into $to:\n\"\"\"\n$text\n\"\"\"",
    )

    func render(_ request: TranslationRequest) -> (system: String, user: String) {
        (fill(system, request), fill(user, request))
    }

    private func fill(_ template: String, _ request: TranslationRequest) -> String {
        template
            .replacingOccurrences(of: "$to", with: request.target.englishName)
            .replacingOccurrences(of: "$from", with: request.source.englishName)
            .replacingOccurrences(of: "$text", with: request.text)
    }
}
