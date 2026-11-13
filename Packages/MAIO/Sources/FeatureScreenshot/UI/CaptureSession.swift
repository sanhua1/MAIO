import AppKit
import MAIOUI
import SwiftUI

/// 截图完成后的输出动作
enum CaptureAction {
    case copy
    case save
    /// 贴图（同时复制）
    case pin
    /// 识别文字（OCR），打开结果窗口；不复制图片
    case ocr
    /// 识别文字后直接交给翻译窗口；不复制图片
    case translate
    /// 长截图：从选区开始往下滚动拼接
    case scrolling
    /// 录屏（MP4 / GIF）
    case record

    var recognizesText: Bool {
        self == .ocr || self == .translate
    }
}

/// 重新编辑已有截图的标注（从贴图或历史打开）：选区固定为图片的位置，底图是原图而不是屏幕
struct EditContext {
    /// 原图和它在屏幕上的位置
    let source: EffectSource
    /// 原图所在的全局矩形（pt）
    let rect: CGRect
    /// 已有的标注（全局坐标）
    let annotations: [Annotation]
}

/// 截图结果
struct CaptureResult: @unchecked Sendable {
    /// 裁剪后的原图（物理像素，不含标注）
    let original: CGImage
    /// 带标注的最终图；没有标注时为 nil（最终图就是原图）
    let rendered: CGImage?
    /// 标注对象，坐标相对截图左上角，单位 pt
    let annotations: [Annotation]
    /// 每 pt 的像素数
    let scale: CGFloat
    /// 截图在屏幕上的位置（全局坐标，pt），贴图时原地出现
    let frame: CGRect

    var finalImage: CGImage {
        rendered ?? original
    }
}

/// 一次截图的结果
enum CaptureOutcome {
    case cancelled
    /// 截图时按 F2：退出截图并打开截图历史（不切回原来的 App）
    case openHistory
    /// 截图时按 F1：整个屏幕复制（和普通复制一样，另外提示"已复制全屏截图"）
    case fullScreen(CaptureResult)
    /// 复制颜色值
    case color(String)
    case image(CaptureResult, CaptureAction)
}

/// 一次区域截图的交互（ADR-0011）：在冻结画面上框选、识别窗口和控件、取色、标注，最后交出结果。
/// 输出（复制、保存、写历史）由 ScreenshotController 负责。
/// 鼠标键盘见 +Input，标注见 +Annotation，识别见 +Detection，绘制见 +Rendering。
@MainActor
final class CaptureSession: OverlayEventHandler {
    struct Options {
        var alwaysDetectControls: Bool
        var showMagnifier: Bool
        var colorFormat: ColorFormat
    }

    struct ElementRequest {
        var point: CGPoint
        var pid: Int32
        var clip: CGRect
    }

    struct Callbacks {
        var colorFormatChanged: (ColorFormat) -> Void
        var toolStyleChanged: (ToolStyle) -> Void
        var finished: (CaptureOutcome) -> Void
    }

    let frozen: [FrozenDisplay]
    let panels: [OverlayPanel]
    let windows: [WindowInfo]
    let locator: ElementLocator
    var options: Options
    let callbacks: Callbacks
    /// 重新编辑模式（nil 表示普通截图）
    let edit: EditContext?

    var interaction = CaptureInteraction()
    var editor = AnnotationEditor()
    let effectCache = EffectCache()
    let textField = AnnotationTextField()
    let toolbarModel = ToolbarModel()
    var highlight: CGRect?
    var cursor: CGPoint
    var color: SampledColor?
    var commandHeld = false
    var shiftAlone = false
    /// 滚轮换算成步数：序号一格一步；大小滚得越多变化越大
    var counterWheel = WheelStepper()
    var sizeWheel = WheelStepper(preciseThreshold: 30, lineThreshold: 1)
    /// 自定义颜色（系统颜色面板）
    let colorPanel = ColorPanelBridge()
    private(set) var finished = false
    var toolbarSize: CGSize?
    var pendingElement: ElementRequest?
    var elementTask: Task<Void, Never>?
    private(set) lazy var toolbar = NSHostingView(rootView: CaptureToolbar(model: toolbarModel))
    /// 鼠标当前停在工具栏的哪一块上（决定指针形状和提示）
    var toolbarHint: ToolbarHint?
    let toolbarTooltip = ToolbarTooltip()

    init(
        frozen: [FrozenDisplay], panels: [OverlayPanel], windows: [WindowInfo], locator: ElementLocator,
        options: Options, toolStyle: ToolStyle, edit: EditContext? = nil, callbacks: Callbacks,
    ) {
        self.edit = edit
        self.frozen = frozen
        self.panels = panels
        self.windows = windows
        self.locator = locator
        self.options = options
        self.callbacks = callbacks
        editor.style = toolStyle
        cursor = Self.globalMouseLocation()
        if let edit, let display = frozen.first(where: { $0.display.bounds.intersects(edit.rect) }) {
            interaction.select(edit.rect, displayBounds: display.display.bounds)
            editor.document.load(edit.annotations)
        }
        toolbarModel.perform = { [weak self] command in self?.perform(command) }
        toolbarModel.hintChanged = { [weak self] hint in self?.toolbarHoverChanged(hint) }
        toolbarModel.capturesScreen = edit == nil
        colorPanel.onChange = { [weak self] color in self?.perform(.color(color)) }
        textField.onChange = { [weak self] in self?.render() }
        textField.onCommit = { [weak self] in
            self?.commitText()
            self?.render()
        }
    }

    // MARK: 显示与结束

    func show() {
        for (panel, display) in zip(panels, frozen) {
            panel.overlayView.handler = self
            panel.overlayView.canvas.setImage(display.image, scale: display.scale)
        }
        commandHeld = NSEvent.modifierFlags.contains(.command)
        syncToolbar()
        updateColor()
        updateHover()
        render()
        for panel in panels {
            panel.orderFrontRegardless()
        }
        // 文字工具要用输入法，遮罩必须成为真正的 key window，所以要激活 MAIO
        AppActivation.activateForcibly()
        let keyPanel = panels.first { $0.overlayView.display.bounds.contains(cursor) } ?? panels.first
        keyPanel?.makeKey()
        keyPanel?.makeFirstResponder(keyPanel?.overlayView)
        NSCursor.crosshair.set()
    }

    func finish(_ outcome: CaptureOutcome) {
        guard !finished else { return }
        finished = true
        elementTask?.cancel()
        _ = textField.finish()
        toolbarModel.clearHover()
        toolbarTooltip.hide()
        toolbar.removeFromSuperview()
        colorPanel.close()
        for panel in panels {
            panel.orderOut(nil)
            panel.overlayView.handler = nil
            panel.overlayView.canvas.setImage(nil, scale: 2)
            panel.overlayView.canvas.hideAll()
        }
        NSCursor.arrow.set()
        callbacks.toolStyleChanged(editor.style)
        callbacks.finished(outcome)
    }

    /// 选区所在显示器的冻结画面
    var selectionDisplay: FrozenDisplay? {
        frozen.first { $0.display.bounds == interaction.bounds }
    }

    func effectSource(for display: FrozenDisplay) -> EffectSource {
        EffectSource(image: display.image, origin: display.display.bounds.origin, scale: display.scale)
    }

    /// 生成结果：原图 + （有标注时）渲染图
    /// 画底图、马赛克和模糊用的来源：重新编辑时是原图，否则是选区所在显示器的冻结画面
    var currentSource: EffectSource? {
        edit?.source ?? selectionDisplay.map(effectSource(for:))
    }

    func makeResult() -> CaptureResult? {
        if let edit {
            return makeEditResult(edit)
        }
        guard let selection = interaction.selection, let display = selectionDisplay else { return nil }
        let aligned = SelectionGeometry.pixelAligned(selection, scale: display.scale)
        let pixels = SelectionGeometry.pixelRect(of: aligned, displayBounds: display.display.bounds, scale: display.scale)
        guard let original = display.image.cropping(to: pixels) else { return nil }
        let items = editor.document.items
        guard !items.isEmpty else {
            return CaptureResult(original: original, rendered: nil, annotations: [], scale: display.scale, frame: aligned)
        }
        let rendered = AnnotationRenderer.renderOutput(items, selection: aligned, source: effectSource(for: display))
        let offset = CGVector(dx: -aligned.minX, dy: -aligned.minY)
        return CaptureResult(
            original: original, rendered: rendered,
            annotations: items.map { $0.transformed(offset: offset, scale: 1) }, scale: display.scale, frame: aligned,
        )
    }

    private func makeEditResult(_ edit: EditContext) -> CaptureResult {
        let items = editor.document.items
        let rendered = items.isEmpty ? nil : AnnotationRenderer.renderOutput(items, selection: edit.rect, source: edit.source)
        let offset = CGVector(dx: -edit.rect.minX, dy: -edit.rect.minY)
        return CaptureResult(
            original: edit.source.image, rendered: rendered,
            annotations: items.map { $0.transformed(offset: offset, scale: 1) }, scale: edit.source.scale, frame: edit.rect,
        )
    }

    func confirm(_ action: CaptureAction) {
        // 重新编辑已有截图时不能长截图、录屏（选区是图片，不是屏幕）
        guard (action != .scrolling && action != .record) || edit == nil else { return }
        if textField.isEditing {
            commitText()
        }
        guard let result = makeResult() else { return }
        finish(.image(result, action))
    }

    func copyColor() {
        guard let color else { return }
        finish(.color(options.colorFormat.string(color)))
    }

    /// NSEvent.mouseLocation（左下角原点）→ 全局坐标（左上角原点）
    static func globalMouseLocation() -> CGPoint {
        let location = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: location.x, y: primaryHeight - location.y)
    }
}
