import AppKit
import MAIOKit
import UniformTypeIdentifiers

/// 截图的总调度：开始截图或重新编辑、复用遮罩窗口、处理输出（复制、保存、写历史、贴图）。
/// 贴图和重新编辑见 +Pins，全屏 / 窗口截图和历史窗口见 +Commands。
@MainActor
final class ScreenshotController {
    /// 正在重新编辑的记录（从贴图或历史打开）
    struct Editing {
        let recordID: String
        /// 从贴图打开时的贴图（编辑期间隐藏，结束后换成新图再显示）
        let pin: PinWindow?
    }

    let context: any FeatureContext
    let history: ScreenshotHistoryStore?
    let pins = PinManager()
    private let locator = ElementLocator()
    private var panels: [CGDirectDisplayID: OverlayPanel] = [:]
    var session: CaptureSession?
    var editing: Editing?
    private var isStarting = false
    /// 截图前最前面的 App：结束后切回去
    private var previousApp: NSRunningApplication?
    var historyWindow: HistoryWindowController?
    let ocrWindows = OCRResultWindows()
    /// 正在进行的长截图
    var scrollCapture: ScrollCaptureSession?

    init(context: any FeatureContext, history: ScreenshotHistoryStore?) {
        self.context = context
        self.history = history
        pins.onAction = { [weak self] pin, action in self?.handle(action, from: pin) }
        let settings = context.settings
        pins.controls = { settings.load(ScreenshotSettings.self).pinControls }
    }

    /// 启用时预先创建遮罩窗口并预热截图接口（spec 5.3），并按上限清理历史
    func prepare() {
        for display in DisplayInfo.all() {
            _ = panel(for: display)
        }
        if context.permissions.isGranted(.screenRecording) {
            Task { await ScreenCapturer.prewarm() }
        }
        enforceHistoryLimit()
    }

    func tearDown() {
        session?.finish(.cancelled)
        session = nil
        pins.closeAll()
        historyWindow?.close()
        historyWindow = nil
        ocrWindows.closeAll()
        scrollCapture?.cancel()
        scrollCapture = nil
        for panel in panels.values {
            panel.close()
        }
        panels.removeAll()
    }

    // MARK: 区域截图

    /// primaryAction：⏎ 做什么（"截图识别文字""截图翻译"命令改成识别 / 翻译）
    func capture(primaryAction: CaptureAction = .copy) async {
        await startSession(primaryAction: primaryAction, edit: nil)
    }

    /// 冻结屏幕并开始交互。edit 不为 nil 时是重新编辑
    func startSession(
        primaryAction: CaptureAction = .copy, edit: (@MainActor ([FrozenDisplay]) -> EditContext?)?,
    ) async {
        guard session == nil, scrollCapture == nil, !isStarting, ensurePermission() else { return }
        isStarting = true
        defer { isStarting = false }
        let started = ContinuousClock.now
        previousApp = Self.frontmostOtherApp()
        let displays = DisplayInfo.all()
        let windows = WindowPicker.candidates(
            WindowSnapshot.current(), excludingPID: getpid(), displays: displays.map(\.bounds),
        )
        let frozen: [FrozenDisplay]
        do {
            frozen = try await ScreenCapturer.capture(displays)
        } catch {
            report(error)
            restoreEditingPin()
            return
        }
        guard !frozen.isEmpty else { return }
        let settings = context.settings.load(ScreenshotSettings.self)
        let session = CaptureSession(
            frozen: frozen,
            panels: frozen.map { panel(for: $0.display) },
            windows: windows,
            locator: locator,
            options: .init(
                alwaysDetectControls: settings.alwaysDetectControls,
                showMagnifier: settings.showMagnifier,
                colorFormat: settings.colorFormat,
                primaryAction: primaryAction,
            ),
            toolStyle: settings.toolStyle,
            edit: edit?(frozen),
            callbacks: .init(
                colorFormatChanged: { [weak self] format in self?.update { $0.colorFormat = format } },
                toolStyleChanged: { [weak self] style in self?.update { $0.toolStyle = style } },
                finished: { [weak self] outcome in self?.complete(outcome) },
            ),
        )
        self.session = session
        session.show()
        let elapsed = ContinuousClock.now - started
        context.logger.info("截图遮罩出现用时 \(elapsed.formatted(.units(allowed: [.milliseconds])), privacy: .public)")
    }

    // MARK: 输出

    private func complete(_ outcome: CaptureOutcome) {
        session = nil
        let previous = previousApp
        previousApp = nil
        let editing = editing
        self.editing = nil
        switch outcome {
        case .cancelled:
            editing?.pin?.orderFrontRegardless()
            previous?.activate()
        case let .color(text):
            ImageExporter.copyToPasteboard(text: text)
            previous?.activate()
            context.overlay.showHUD("已复制颜色 \(text)", symbol: "eyedropper")
        case let .image(result, .scrolling):
            previous?.activate()
            beginScrollCapture(from: result, sourceApp: previous?.bundleIdentifier)
        case let .image(result, action):
            let asksLocation = action == .save && context.settings.load(ScreenshotSettings.self).askSaveLocation
            // 识别文字时接着会打开 MAIO 的结果窗口或翻译窗口，不切回原 App
            if !asksLocation, !action.recognizesText {
                previous?.activate()
            }
            Task {
                let recordID = await output(
                    result, action: action, sourceApp: previous?.bundleIdentifier, asksLocation: asksLocation,
                    updating: editing?.recordID, copies: !action.recognizesText,
                )
                finishPinning(result: result, action: action, recordID: recordID, editing: editing)
                if asksLocation {
                    previous?.activate()
                }
                if action.recognizesText {
                    await recognize(result.finalImage, recordID: recordID, translate: action == .translate)
                }
            }
        }
    }

    /// 自动复制 → 需要时保存文件 → 写入（或更新）历史。返回历史记录 id
    @discardableResult
    func output(
        _ result: CaptureResult, action: CaptureAction, sourceApp: String?, asksLocation: Bool = false,
        updating recordID: String? = nil, copies: Bool = true,
    ) async -> String? {
        let encoded = await Task.detached(priority: .userInitiated) { EncodedCapture(result) }.value
        guard let encoded else {
            context.overlay.showError("截图编码失败")
            return nil
        }
        if copies {
            ImageExporter.copyToPasteboard(png: encoded.final)
        }
        let date = Date()
        let settings = context.settings.load(ScreenshotSettings.self)
        if action == .save || (settings.autoSave && copies) {
            save(encoded.final, date: date, asksLocation: asksLocation, announce: action == .save)
        }
        let id = await record(encoded, result: result, sourceApp: sourceApp, date: date, updating: recordID)
        historyWindow?.reload()
        return id
    }

    private func record(
        _ encoded: EncodedCapture, result: CaptureResult, sourceApp: String?, date: Date, updating recordID: String?,
    ) async -> String? {
        guard let history else { return nil }
        do {
            if let recordID {
                try await history.update(id: recordID, rendered: encoded.rendered, annotations: encoded.annotations)
                return recordID
            }
            let record = try await history.add(
                .init(
                    original: encoded.original, rendered: encoded.rendered, annotations: encoded.annotations,
                    pixelWidth: result.original.width, pixelHeight: result.original.height, scale: result.scale,
                ),
                sourceApp: sourceApp, date: date,
            )
            try await history.enforce(limit: context.settings.load(ScreenshotSettings.self).historyLimit.bytes)
            return record.id
        } catch {
            context.logger.error("写入截图历史失败：\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func enforceHistoryLimit() {
        guard let history else { return }
        let limit = context.settings.load(ScreenshotSettings.self).historyLimit.bytes
        Task {
            _ = try? await history.enforce(limit: limit)
            historyWindow?.reload()
        }
    }

    // MARK: 辅助

    func ensurePermission() -> Bool {
        guard context.permissions.isGranted(.screenRecording) else {
            context.permissions.request(.screenRecording)
            context.overlay.showError("截图需要「屏幕与系统录音」权限。授权后请退出并重新打开 MAIO（系统要求）")
            return false
        }
        return true
    }

    func report(_ error: any Error) {
        context.logger.error("截图失败：\(error.localizedDescription, privacy: .public)")
        context.overlay.showError("截图失败：\(error.localizedDescription)")
    }

    private func update(_ change: (inout ScreenshotSettings) -> Void) {
        var settings = context.settings.load(ScreenshotSettings.self)
        let before = settings
        change(&settings)
        if settings != before {
            context.settings.save(settings)
        }
    }

    /// 复用遮罩窗口；显示器的位置或大小变化时更新
    private func panel(for display: DisplayInfo) -> OverlayPanel {
        let frame = NSScreen.screens.first { $0.displayID == display.id }?.frame ?? display.bounds
        if let panel = panels[display.id] {
            panel.overlayView.update(display: display)
            if panel.frame != frame {
                panel.setFrame(frame, display: false)
            }
            return panel
        }
        let panel = OverlayPanel(display: display, frame: frame)
        panels[display.id] = panel
        return panel
    }

    static func frontmostOtherApp() -> NSRunningApplication? {
        let app = NSWorkspace.shared.frontmostApplication
        return app?.processIdentifier == getpid() ? nil : app
    }
}

// MARK: 保存文件

extension ScreenshotController {
    func save(_ png: Data, date: Date, asksLocation: Bool, announce: Bool) {
        let settings = context.settings.load(ScreenshotSettings.self)
        let directory = settings.saveDirectory.isEmpty
            ? ImageExporter.defaultDirectory()
            : URL(fileURLWithPath: settings.saveDirectory, isDirectory: true)
        do {
            let url: URL
            if asksLocation {
                guard let chosen = Self.askSaveLocation(directory: directory, date: date) else { return }
                try png.write(to: chosen, options: .atomic)
                url = chosen
            } else {
                url = try ImageExporter.save(png: png, toDirectory: directory, date: date)
            }
            if announce {
                context.overlay.showHUD("已保存：\(url.lastPathComponent)", symbol: "square.and.arrow.down")
            }
        } catch {
            context.overlay.showError("保存截图失败：\(error.localizedDescription)")
        }
    }

    private static func askSaveLocation(directory: URL, date: Date) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.directoryURL = directory
        panel.nameFieldStringValue = ScreenshotFileName.make(date: date) { _ in false }
        panel.level = .modalPanel
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// 在后台编码好的结果
struct EncodedCapture: Sendable {
    let original: Data
    let rendered: Data?
    let annotations: Data?

    /// 复制、保存用的最终图
    var final: Data {
        rendered ?? original
    }

    init?(_ result: CaptureResult) {
        guard let original = ImageExporter.pngData(result.original) else { return nil }
        self.original = original
        rendered = result.rendered.flatMap(ImageExporter.pngData)
        annotations = result.annotations.isEmpty ? nil : try? JSONEncoder().encode(result.annotations)
    }
}
