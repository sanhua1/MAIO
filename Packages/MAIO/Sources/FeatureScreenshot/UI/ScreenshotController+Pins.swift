import AppKit
import MAIOKit

/// 贴图（spec F5、F12）和重新编辑标注。
extension ScreenshotController {
    /// 截图或编辑结束后：⌘P 贴出新图；从贴图打开的编辑，把贴图换成新图
    func finishPinning(result: CaptureResult, action: CaptureAction, recordID: String?, editing: Editing?) {
        if let pin = editing?.pin {
            pin.replace(image: result.finalImage, scale: result.scale)
            pin.orderFrontRegardless()
            return
        }
        guard action == .pin else { return }
        pins.pin(
            image: result.finalImage, scale: result.scale, contentRect: result.frame, recordID: recordID,
            showsShadow: context.settings.load(ScreenshotSettings.self).pinShadow,
        )
    }

    /// 编辑没能开始（例如截图失败）时，把隐藏的贴图显示回来
    func restoreEditingPin() {
        editing?.pin?.orderFrontRegardless()
        editing = nil
    }

    // MARK: 命令

    /// 把剪贴板里的图片（或文字渲染成的图片）贴到屏幕上，写入历史；内容本来就在剪贴板上，不再复制
    func pinClipboard() async {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let content = PasteboardImage.read(screenScale: scale) else {
            context.overlay.showHUD("剪贴板里没有图片或文字", symbol: "doc.on.clipboard")
            return
        }
        await pin(content)
    }

    /// 契约 screenshot.pin：贴指定的图片文件或文字（剪贴板历史右键贴图）
    func pin(_ input: ScreenshotPinContract.Input) async throws {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let content: PasteboardImage.Content? = if let path = input.imagePath {
            PasteboardImage.read(fileAt: URL(fileURLWithPath: path))
        } else if let text = input.text, !text.isEmpty {
            PasteboardImage.render(text: text, scale: scale)
        } else {
            nil
        }
        guard let content else {
            throw CommandError.invalidArgument(key: "imagePath", reason: "没有可以贴的图片或文字")
        }
        await pin(content)
    }

    /// 贴图并写入历史，不复制（内容来自剪贴板）
    private func pin(_ content: PasteboardImage.Content) async {
        let size = CGSize(
            width: CGFloat(content.image.width) / content.scale,
            height: CGFloat(content.image.height) / content.scale,
        )
        let (rect, zoom) = PinManager.centeredRect(for: size)
        let result = CaptureResult(original: content.image, rendered: nil, annotations: [], scale: content.scale, frame: rect)
        let recordID = await output(
            result, action: .pin, sourceApp: Self.frontmostOtherApp()?.bundleIdentifier, copies: false,
        )
        let pin = pins.pin(
            image: content.image, scale: content.scale, contentRect: rect, recordID: recordID,
            showsShadow: context.settings.load(ScreenshotSettings.self).pinShadow,
        )
        if zoom < 1 {
            pin.apply { $0.zoom = zoom }
        }
    }

    /// 重新贴最近一张截图
    func pinLast() async {
        guard let record = await history?.records.first else {
            context.overlay.showHUD("还没有截图历史", symbol: "photo.on.rectangle")
            return
        }
        await pinRecord(record.id)
    }

    /// 从历史贴图（同时复制，spec：贴图时自动复制）
    func pinRecord(_ id: String) async {
        guard let history, let record = await history.record(id: id),
              let image = await Self.loadImage(history.finalImageURL(for: record)) else { return }
        let scale = CGFloat(record.scale ?? Double(NSScreen.main?.backingScaleFactor ?? 2))
        let size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let (rect, zoom) = PinManager.centeredRect(for: size)
        let pin = pins.pin(
            image: image, scale: scale, contentRect: rect, recordID: id,
            showsShadow: context.settings.load(ScreenshotSettings.self).pinShadow,
        )
        if zoom < 1 {
            pin.apply { $0.zoom = zoom }
        }
        if let png = ImageExporter.pngData(image) {
            ImageExporter.copyToPasteboard(png: png)
        }
    }

    // MARK: 贴图窗口的操作

    func handle(_ action: PinAction, from pin: PinWindow) {
        switch action {
        case .copy:
            if let png = ImageExporter.pngData(pin.outputImage) {
                ImageExporter.copyToPasteboard(png: png)
                context.overlay.showHUD("已复制贴图", symbol: "doc.on.doc")
            }
        case .save:
            guard let png = ImageExporter.pngData(pin.outputImage) else { return }
            save(png, date: Date(), asksLocation: context.settings.load(ScreenshotSettings.self).askSaveLocation, announce: true)
        case .edit:
            guard let recordID = pin.recordID else { return }
            Task { await beginEdit(recordID: recordID, pin: pin) }
        case .ocr, .translate:
            let image = pin.outputImage
            Task { await recognize(image, recordID: pin.recordID, translate: action == .translate) }
        case .close:
            pins.close(pin)
        case .closeAll:
            pins.closeAll()
        }
    }

    // MARK: 重新编辑

    /// 打开已有截图的标注编辑：从贴图打开时就在贴图的位置编辑，否则放在屏幕中间
    func beginEdit(recordID: String, pin: PinWindow?) async {
        guard session == nil, let history, let record = await history.record(id: recordID),
              let original = await Self.loadImage(history.originalURL(for: recordID)) else { return }
        let stored = await history.annotations(for: recordID)
        let recordScale = CGFloat(record.scale ?? 2)
        let pinCenter = pin.map { CGPoint(x: $0.contentRect.midX, y: $0.contentRect.midY) }
        editing = Editing(recordID: recordID, pin: pin)
        // 先隐藏贴图，免得它被截进背景里
        pin?.orderOut(nil)
        await startSession { frozen in
            Self.editContext(
                original: original, recordScale: recordScale, annotations: stored, center: pinCenter, frozen: frozen,
            )
        }
    }

    /// 选一个显示器放下原图：按显示器的缩放 1:1 显示，放不下时缩小；标注从记录的坐标换算过来
    static func editContext(
        original: CGImage, recordScale: CGFloat, annotations: [Annotation], center: CGPoint?, frozen: [FrozenDisplay],
    ) -> EditContext? {
        let anchor = center ?? CaptureSession.globalMouseLocation()
        guard let display = frozen.first(where: { $0.display.bounds.contains(anchor) }) ?? frozen.first else { return nil }
        let bounds = display.display.bounds
        let pixels = CGSize(width: original.width, height: original.height)
        // 每 pt 的像素数：默认和显示器一致（1:1），图太大时增大（缩小显示）
        let scale = max(display.scale, pixels.width / (bounds.width * 0.9), pixels.height / (bounds.height * 0.9))
        let size = CGSize(width: (pixels.width / scale).rounded(), height: (pixels.height / scale).rounded())
        let middle = center ?? CGPoint(x: bounds.midX, y: bounds.midY)
        let origin = CGPoint(
            x: min(max(middle.x - size.width / 2, bounds.minX), bounds.maxX - size.width).rounded(),
            y: min(max(middle.y - size.height / 2, bounds.minY), bounds.maxY - size.height).rounded(),
        )
        let rect = CGRect(origin: origin, size: size)
        let factor = recordScale / scale
        let items = annotations.map { annotation in
            annotation.transformed(offset: .zero, scale: factor).moved(by: CGVector(dx: origin.x, dy: origin.y))
        }
        return EditContext(source: EffectSource(image: original, origin: origin, scale: scale), rect: rect, annotations: items)
    }

    static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
