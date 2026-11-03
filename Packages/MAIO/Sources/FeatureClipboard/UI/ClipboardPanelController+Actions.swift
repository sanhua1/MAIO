import AppKit
import MAIOKit

/// 右键菜单里的复制、贴图、翻译。贴图和翻译通过其他功能的契约完成（ARCHITECTURE §4.3）。
extension ClipboardPanelController {
    func handle(_ action: ClipRowAction, for item: ClipItem) {
        close(restoreFocus: action == .copy)
        Task {
            do {
                let payload = try await store.payload(item.id)
                switch action {
                case .copy:
                    paster.write(payload)
                    monitor.skipCurrent()
                case .pinToScreen:
                    try await pin(payload)
                case .translate:
                    guard let text = payload.plainText else { return }
                    _ = try await commands.perform(TranslateTextContract.self, .init(text: text))
                default:
                    break
                }
            } catch {
                logger("剪贴板操作失败：\(error.localizedDescription)")
            }
        }
    }

    /// 图片写到临时文件交给截图功能，用完删除；文字直接传过去渲染成图片
    private func pin(_ payload: ClipPayload) async throws {
        if let image = payload.data(PasteType.png) ?? payload.data(PasteType.tiff) {
            let suffix = payload.data(PasteType.png) != nil ? "png" : "tiff"
            let url = FileManager.default.temporaryDirectory.appending(path: "maio-clip-pin-\(UUID().uuidString).\(suffix)")
            try image.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            _ = try await commands.perform(ScreenshotPinContract.self, .init(imagePath: url.path))
        } else if let text = payload.plainText {
            _ = try await commands.perform(ScreenshotPinContract.self, .init(text: text))
        }
    }
}
