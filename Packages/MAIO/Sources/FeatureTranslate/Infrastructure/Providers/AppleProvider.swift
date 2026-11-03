import Foundation
import Translation

/// Apple 系统翻译（离线）。需要用户先在系统设置里下载对应的语言包，MAIO 不会自动下载。
struct AppleProvider: TranslationProvider {
    func translate(_ request: TranslationRequest, onPartial _: @escaping @Sendable (String) -> Void) async throws
        -> TranslationResult {
        let sourceLanguage = request.source == .auto ? request.detected : request.source
        guard let sourceLanguage, sourceLanguage != .auto else {
            throw TranslationError.service("无法识别原文语言，请在窗口上方手动选择源语言")
        }
        let source = Locale.Language(identifier: sourceLanguage.rawValue)
        let target = Locale.Language(identifier: request.target.rawValue)
        let status = await LanguageAvailability().status(from: source, to: target)
        switch status {
        case .installed:
            break
        case .supported:
            throw TranslationError.service(
                "还没有下载\(sourceLanguage.displayName)或\(request.target.displayName)的语言包："
                    + "请在「系统设置 → 通用 → 语言与地区 → 翻译语言」中下载",
            )
        default:
            throw TranslationError.service("Apple 翻译不支持\(sourceLanguage.displayName) → \(request.target.displayName)")
        }
        let session = TranslationSession(installedSource: source, target: target)
        let response = try await session.translate(request.text)
        return TranslationResult(text: response.targetText)
    }
}
