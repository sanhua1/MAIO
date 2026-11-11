import AppKit
import MAIOKit

/// 识别文字（spec F7）和截图翻译（F8）。
extension ScreenshotController {
    /// 识别图片里的文字，写入这条历史（用于搜索）。translate 为 true 时直接交给翻译窗口，否则打开结果窗口。
    func recognize(_ image: CGImage, recordID: String?, translate: Bool) async {
        context.overlay.showHUD("正在识别文字…", symbol: "text.viewfinder")
        let started = ContinuousClock.now
        let text: String
        do {
            text = try await TextRecognizer.recognize(image)
        } catch {
            context.logger.error("识别文字失败：\(error.localizedDescription, privacy: .public)")
            context.overlay.showError("识别文字失败：\(error.localizedDescription)")
            return
        }
        let elapsed = (ContinuousClock.now - started).formatted(.units(allowed: [.seconds, .milliseconds]))
        // 识别没有文字时不打开任何窗口，用醒目的提示，免得用户以为点了没反应
        guard !text.isEmpty else {
            context.overlay.showError("没有识别到文字")
            context.logger.info("识别文字：没有文字（translate=\(translate)，用时 \(elapsed, privacy: .public)）")
            return
        }
        context.logger.info("识别文字：\(text.count) 字（translate=\(translate)，用时 \(elapsed, privacy: .public)）")
        if let recordID, let history {
            try? await history.setOCRText(text, id: recordID)
            historyWindow?.reload()
        }
        if translate {
            await self.translate(text)
        } else {
            showOCRResult(text)
        }
    }

    func showOCRResult(_ text: String) {
        let model = OCRResultModel(text: text)
        model.translate = { [weak self] text in Task { await self?.translate(text) } }
        model.copied = { [weak self] in self?.context.overlay.showHUD("已复制文字", symbol: "doc.on.doc") }
        ocrWindows.show(model)
    }

    /// 通过契约交给翻译功能（ARCHITECTURE §4.3）
    func translate(_ text: String) async {
        context.logger.info("截图翻译：交给翻译功能（\(text.count) 字）")
        do {
            _ = try await context.commands.perform(TranslateTextContract.self, .init(text: text))
            context.logger.info("截图翻译：翻译功能已处理")
        } catch {
            context.logger.error("截图翻译失败：\(error.localizedDescription, privacy: .public)")
            context.overlay.showError("打开翻译失败：\(error.localizedDescription)")
        }
    }

    /// 历史记录：识别文字或翻译
    func recognizeRecord(_ id: String, translate: Bool) async {
        guard let history, let record = await history.record(id: id),
              let image = await Self.loadImage(history.finalImageURL(for: record)) else { return }
        await recognize(image, recordID: id, translate: translate)
    }
}
