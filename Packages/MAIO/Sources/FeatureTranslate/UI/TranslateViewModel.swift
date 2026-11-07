import Foundation
import MAIOKit
import Observation

/// 翻译窗口的状态：原文、语言、各翻译源的结果卡片。所有启用的源并行请求，先返回的先显示。
@MainActor
@Observable
final class TranslateViewModel {
    struct Card: Identifiable, Equatable {
        enum Phase: Equatable {
            case loading
            /// 大模型逐字输出中
            case streaming(String)
            case done(TranslationResult)
            case failed(String)
        }

        let id: String
        let name: String
        let symbol: String
        var phase: Phase = .loading
        var isCollapsed = false

        var text: String? {
            switch phase {
            case let .streaming(text): text
            case let .done(result): result.text
            default: nil
            }
        }
    }

    var sourceText = ""
    /// 用户选择的源语言（`.auto` 为自动检测）
    var sourceLanguage: Language = .auto
    /// 用户选择的目标语言（nil 表示按设置自动选择）
    var targetOverride: Language?
    private(set) var detected: Language?
    private(set) var effectiveTarget: Language = .simplifiedChinese
    private(set) var cards: [Card] = []
    var isPinned = false
    var fontSize = 14.0
    /// 每次打开窗口加一，用于让输入框重新获得焦点
    private(set) var focusToken = 0

    @ObservationIgnored var onClose: (() -> Void)?
    @ObservationIgnored private var run: Task<Void, Never>?
    @ObservationIgnored private let environment: Environment

    struct Environment {
        let settings: () -> TranslateSettings
        let factory: ProviderFactory
        let history: HistoryStore
    }

    init(environment: Environment) {
        self.environment = environment
    }

    func prepare(text: String?) {
        let settings = environment.settings()
        fontSize = settings.fontSize
        focusToken += 1
        guard let text else { return }
        sourceText = settings.removeLineBreaks ? TextCleaner.removingLineBreaks(text) : text
    }

    func removeLineBreaks() {
        sourceText = TextCleaner.removingLineBreaks(sourceText)
        translate()
    }

    func swapLanguages() {
        let currentSource = sourceLanguage == .auto ? detected : sourceLanguage
        guard let currentSource else { return }
        sourceLanguage = effectiveTarget
        targetOverride = currentSource
        translate()
    }

    func toggleCollapsed(_ id: Card.ID) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index].isCollapsed.toggle()
    }

    func cancel() {
        run?.cancel()
        run = nil
    }

    func retry(_ id: Card.ID) {
        let settings = environment.settings()
        guard let config = settings.services.first(where: { $0.id == id }),
              let request = currentRequest(settings: settings)
        else { return }
        update(id) { $0.phase = .loading }
        let provider = environment.factory.make(config)
        Task { [weak self] in await self?.perform(provider, id: id, request: request) }
    }

    func translate() {
        cancel()
        let settings = environment.settings()
        guard let request = currentRequest(settings: settings) else {
            cards = []
            return
        }
        let services = settings.services.filter(\.isEnabled)
        let previous = Dictionary(cards.map { ($0.id, $0.isCollapsed) }, uniquingKeysWith: { first, _ in first })
        cards = services.map { config in
            Card(id: config.id, name: config.name, symbol: config.spec.symbol, isCollapsed: previous[config.id] ?? false)
        }
        let jobs = services.map { (id: $0.id, provider: environment.factory.make($0)) }
        run = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                for job in jobs {
                    group.addTask { await self?.perform(job.provider, id: job.id, request: request) }
                }
            }
            guard !Task.isCancelled else { return }
            self?.recordHistory(request, settings: settings)
        }
    }

    private func currentRequest(settings: TranslateSettings) -> TranslationRequest? {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        detected = LanguageDetector.detect(text)
        let known = sourceLanguage == .auto ? detected : sourceLanguage
        effectiveTarget = targetOverride ?? TargetLanguagePolicy.target(
            detected: known, preferred: settings.targetLanguage, second: settings.secondTargetLanguage,
        )
        return TranslationRequest(text: text, source: sourceLanguage, target: effectiveTarget, detected: detected)
    }

    private nonisolated func perform(_ provider: any TranslationProvider, id: String, request: TranslationRequest) async {
        do {
            let result = try await provider.translate(request) { [weak self] partial in
                Task { @MainActor in
                    self?.update(id) { card in
                        if case .loading = card.phase {
                            card.phase = .streaming(partial)
                        }
                        if case .streaming = card.phase {
                            card.phase = .streaming(partial)
                        }
                    }
                }
            }
            await update(id) { $0.phase = .done(result) }
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled {
                return
            }
            let message = (error as? TranslationError)?.message ?? Self.describe(error)
            await update(id) { $0.phase = .failed(message) }
        }
    }

    private func update(_ id: Card.ID, _ change: (inout Card) -> Void) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        change(&cards[index])
    }

    nonisolated static func describe(_ error: any Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return "请求超时，请检查网络或代理"
            case .notConnectedToInternet: return "没有网络连接"
            case .cannotFindHost, .cannotConnectToHost: return "无法连接到服务器（可能需要代理）"
            case .cancelled: return "已取消"
            default: break
            }
        }
        return error.localizedDescription
    }

    private func recordHistory(_ request: TranslationRequest, settings: TranslateSettings) {
        guard settings.historyEnabled else { return }
        let items = cards.compactMap { card -> HistoryEntry.Item? in
            guard case let .done(result) = card.phase, !result.text.isEmpty else { return nil }
            return HistoryEntry.Item(service: card.name, text: result.text)
        }
        guard !items.isEmpty else { return }
        let entry = HistoryEntry(
            date: Date(), text: request.text, source: request.detected ?? request.source,
            target: request.target, results: items,
        )
        environment.history.add(entry, limit: settings.historyLimit)
    }
}
