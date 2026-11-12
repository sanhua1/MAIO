import AppKit
import CoreMedia
import MAIOKit

/// 一次录屏（ADR-0024）：选区下方出现控制条 → 选格式和声音 → 开始 → 完成 / 放弃。
/// - 开始前接管键盘（⏎ 开始、Esc 取消）；开始后立即交还，录制中的按键照常打到下面的 App；
/// - 录制中用控制条上的按钮，或者再触发一次「录屏」命令结束。
@MainActor
final class RecordingSession {
    enum Outcome {
        case saved(URL)
        case cancelled
        case failed(String)
    }

    private enum Writer {
        case movie(MovieWriter)
        case gif(GIFWriter)

        var sink: any RecordingSink {
            switch self {
            case let .movie(writer): writer
            case let .gif(writer): writer
            }
        }

        func finish() async throws {
            let end = CMClockGetTime(CMClockGetHostTimeClock())
            switch self {
            case let .movie(writer): try await writer.finish(at: end)
            case let .gif(writer): try await writer.finish(at: end.seconds)
            }
        }

        func discard() {
            switch self {
            case let .movie(writer): writer.discard()
            case let .gif(writer): writer.discard()
            }
        }
    }

    private let rect: CGRect
    private let scale: CGFloat
    private let display: DisplayInfo
    private let directory: URL
    private let model: RecordingModel
    private let frame: RecordingFrame
    private var keyboard: (any KeyboardSession)?
    private var keys: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var recorder: ScreenRecorder?
    private var writer: Writer?
    private var url: URL?
    private var done = false
    private let remember: (RecordingOptions) -> Void
    private let completion: (Outcome) -> Void

    var isSettingUp: Bool {
        model.phase == .setup
    }

    init(
        rect: CGRect, scale: CGFloat, display: DisplayInfo, options: RecordingOptions, directory: URL,
        input: any InputService, remember: @escaping (RecordingOptions) -> Void,
        completion: @escaping (Outcome) -> Void,
    ) {
        self.rect = rect
        self.scale = scale
        self.display = display
        self.directory = directory
        self.remember = remember
        self.completion = completion
        model = RecordingModel(options: options, points: rect.size, scale: scale)
        frame = RecordingFrame(rect: rect, model: model)
        keyboard = input.beginKeyboardSession()
        model.start = { [weak self] in Task { await self?.begin() } }
        model.stop = { [weak self] in Task { await self?.stop() } }
        model.cancel = { [weak self] in self?.cancel() }
    }

    func show() {
        frame.show()
        keys = Task { [weak self, keyboard] in
            guard let keyboard else { return }
            for await event in keyboard.events where event.kind == .down {
                switch event.keyCode {
                case 36, 76: await self?.begin()
                case 53: self?.cancel()
                default: break
                }
            }
        }
    }

    // MARK: 开始

    private func begin() async {
        guard model.phase == .setup, !done else { return }
        var options = model.options
        remember(options)
        if options.format == .mp4, options.microphone, await !MicrophoneAccess.request() {
            model.message = "麦克风没有授权：系统设置 › 隐私与安全性 › 麦克风"
            MicrophoneAccess.openSettings()
            return
        }
        guard model.phase == .setup, !done else { return }
        endKeyboard()
        model.phase = .recording
        options = model.options
        do {
            try await startRecording(options)
        } catch {
            fail("录屏失败：\(error.localizedDescription)")
            return
        }
        guard !done else { return }
        frame.setRecording(true)
        let started = ContinuousClock.now
        ticker = Task { [weak self] in
            while !Task.isCancelled, let model = self?.model {
                model.elapsed = ContinuousClock.now - started
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func startRecording(_ options: RecordingOptions) async throws {
        let size = RecordingGeometry.outputSize(points: rect.size, scale: scale, options: options)
        let url = try RecordingFiles.makeURL(in: directory, format: options.format, date: Date())
        self.url = url
        let writer: Writer = switch options.format {
        case .mp4: try .movie(MovieWriter(url: url, size: size, options: options))
        case .gif: try .gif(GIFWriter(url: url, size: size))
        }
        self.writer = writer
        let request = ScreenRecorder.Request(rect: rect, display: display, size: size, options: options)
        recorder = try await ScreenRecorder.start(request, sink: writer.sink) { [weak self] _ in
            // 流被系统停掉（显示器休眠、权限被收回）：保存已经录到的部分
            Task { @MainActor in await self?.stop() }
        }
        if done {
            // 启动期间用户点了放弃
            await recorder?.stop()
            writer.discard()
            removeFile()
        }
    }

    // MARK: 结束

    func stop() async {
        guard model.phase == .recording, !done, let writer else { return }
        model.phase = .saving
        ticker?.cancel()
        await recorder?.stop()
        do {
            try await writer.finish()
            guard let url else { return }
            close(.saved(url))
        } catch {
            removeFile()
            close(.failed("录屏保存失败：\(error.localizedDescription)"))
        }
    }

    func cancel() {
        guard !done else { return }
        let recorder = recorder
        let writer = writer
        if let writer {
            Task {
                await recorder?.stop()
                writer.discard()
            }
            removeFile()
        }
        close(.cancelled)
    }

    private func fail(_ message: String) {
        let recorder = recorder
        Task { await recorder?.stop() }
        writer?.discard()
        removeFile()
        close(.failed(message))
    }

    private func close(_ outcome: Outcome) {
        guard !done else { return }
        done = true
        ticker?.cancel()
        endKeyboard()
        frame.close()
        completion(outcome)
    }

    private func endKeyboard() {
        keys?.cancel()
        keys = nil
        keyboard?.end()
        keyboard = nil
    }

    private func removeFile() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
