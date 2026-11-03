import AppKit
import MAIOKit

/// 长截图（spec F10）：结束后先写入历史（不会丢），再打开标注编辑，之后复制、保存、贴图和普通截图一样。
extension ScreenshotController {
    func beginScrollCapture(from result: CaptureResult, sourceApp: String?) {
        guard let display = DisplayInfo.all().first(where: { $0.bounds.intersects(result.frame) }) else { return }
        let capture = ScrollCaptureSession(
            rect: result.frame, scale: result.scale, input: context.input,
        ) { [weak self] image in
            self?.scrollCapture = nil
            guard let image else {
                self?.context.overlay.showError("长截图失败：没有截到内容")
                return
            }
            Task { await self?.finishScrollCapture(image, scale: result.scale, frame: result.frame, sourceApp: sourceApp) }
        }
        scrollCapture = capture
        capture.start(display: display)
    }

    private func finishScrollCapture(_ image: CGImage, scale: CGFloat, frame: CGRect, sourceApp: String?) async {
        let size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let result = CaptureResult(
            original: image, rendered: nil, annotations: [], scale: scale, frame: CGRect(origin: frame.origin, size: size),
        )
        context.overlay.showHUD("长截图 \(image.width) × \(image.height)", symbol: "arrow.down.to.line.compact")
        guard let recordID = await output(result, action: .copy, sourceApp: sourceApp, copies: false) else { return }
        await beginEdit(recordID: recordID, pin: nil)
    }
}
