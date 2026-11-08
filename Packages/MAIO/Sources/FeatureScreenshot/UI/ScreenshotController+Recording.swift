import AppKit
import MAIOKit

/// 录屏（ADR-0024）：截图框选好区域后开始；录完保存到录屏文件夹，并把文件复制到剪贴板。
extension ScreenshotController {
    /// 「录屏」命令：没在录就进入框选，录制前 / 录制中再按一次就开始 / 结束
    func toggleRecording() async {
        if let recording {
            await recording.toggle()
            return
        }
        await capture(primaryAction: .record)
    }

    func beginRecording(from result: CaptureResult) {
        guard recording == nil else {
            context.overlay.showError("正在录屏，先结束当前的录制")
            return
        }
        guard let display = DisplayInfo.all().first(where: { $0.bounds.intersects(result.frame) }) else { return }
        let settings = context.settings.load(ScreenshotSettings.self)
        let session = RecordingSession(
            rect: result.frame, scale: result.scale, display: display, options: settings.recordingOptions,
            directory: RecordingFiles.directory(settings.recordDirectory), input: context.input,
            remember: { [weak self] options in self?.update { $0.remember(options) } },
            completion: { [weak self] outcome in self?.finishRecording(outcome) },
        )
        recording = session
        session.show()
    }

    /// 停用功能时：录制中的保存下来，还没开始的直接取消
    func endRecording() {
        guard let recording else { return }
        if recording.isSettingUp {
            recording.cancel()
        } else {
            Task { await recording.stop() }
        }
    }

    private func finishRecording(_ outcome: RecordingSession.Outcome) {
        recording = nil
        switch outcome {
        case let .saved(url):
            RecordingFiles.copyToPasteboard(url)
            context.overlay.showHUD("录屏已保存并复制：\(url.lastPathComponent)", symbol: "record.circle")
        case let .failed(message):
            context.overlay.showError(message)
        case .cancelled:
            break
        }
    }
}
