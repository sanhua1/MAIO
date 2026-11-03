import AppKit
import MAIOKit

/// 识别文字（spec F7）和截图翻译（F8）。
extension ScreenshotController {
    /// 识别图片里的文字，写入这条历史（用于搜索）。translate 为 true 时直接交给翻译窗口，否则打开结果窗口。
    func recognize(_ image: CGImage, recordID: String?, translate: Bool) async {
        context.overlay.showHUD("正在识别文字…", symbol: "text.viewfinder")
        let text: String
        do {
            text = try await TextRecognizer.recognize(image)
        } catch {
            context.logger.error("识别文字失败：\(error.localizedDescription, privacy: .public)")
            context.overlay.showError("识别文字失败：\(error.localizedDescription)")
            return
        }
        guard !text.isEmpty else {
            context.overlay.showHUD("没有识别到文字", symbol: "text.viewfinder")
            return
        }
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
        do {
            _ = try await context.commands.perform(TranslateTextContract.self, .init(text: text))
        } catch {
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
