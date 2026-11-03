import AppKit

/// 贴图的内容：图片（可旋转、缩放）、自绘阴影、悬停边框、缩放比例提示；处理鼠标和键盘。
@MainActor
final class PinView: NSView {
    weak var window_: PinWindow?
    private var isHovered = false
    private var hint: String?
    private var hintTask: Task<Void, Never>?
    /// 滚轮一格 = 一步（开了平滑滚动时一格会变成一串事件）
    private var zoomWheel = WheelStepper()
    private var opacityWheel = WheelStepper()

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self,
        ))
    }

    // MARK: 绘制

    override func draw(_: NSRect) {
        guard let pin = window_, let context = NSGraphicsContext.current?.cgContext else { return }
        let state = pin.state
        let content = bounds.insetBy(dx: PinState.margin, dy: PinState.margin)
        context.saveGState()
        // 阴影：系统主题色的发光（跟着图片的形状，透明圆角也贴合）；悬停或选中时更亮。关掉阴影后就是一张纯粹的图
        if state.showsShadow {
            let strength: CGFloat = isHovered || pin.isKeyWindow ? 0.95 : 0.6
            context.setShadow(
                offset: .zero, blur: 10, color: NSColor.controlAccentColor.withAlphaComponent(strength).cgColor,
            )
        }
        context.interpolationQuality = state.zoom >= 2 ? .none : .high
        context.translateBy(x: content.midX, y: content.midY)
        context.rotate(by: -CGFloat(state.quarterTurns) * .pi / 2)
        let size = CGSize(width: state.imageSize.width * state.zoom, height: state.imageSize.height * state.zoom)
        context.draw(pin.image, in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        context.restoreGState()
        drawHint(in: content)
    }

    private func drawHint(in content: CGRect) {
        guard let hint else { return }
        let text = NSAttributedString(string: hint, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white,
        ])
        let size = text.size()
        let box = CGRect(x: content.minX + 6, y: content.maxY - size.height - 12, width: size.width + 12, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        text.draw(at: CGPoint(x: box.minX + 6, y: box.minY + 3))
    }

    /// 短暂显示提示（缩放比例、透明度）
    func flash(_ text: String) {
        hint = text
        needsDisplay = true
        hintTask?.cancel()
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.hint = nil
            self?.needsDisplay = true
        }
    }

    // MARK: 鼠标

    override func mouseEntered(with _: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with _: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        if event.clickCount >= 2 {
            window_?.perform(.close)
            return
        }
        window?.performDrag(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let pin = window_ else { return }
        NSMenu.popUpContextMenu(PinMenu.make(for: pin), with: event, for: self)
    }

    /// 修饰键 + 滚轮：缩放（以鼠标为中心）或调透明度，每格 5%。用哪个修饰键在设置里改（默认 ⌃ 缩放、⌘ 透明度）
    override func scrollWheel(with event: NSEvent) {
        guard let pin = window_, let target = Self.target(for: event.modifierFlags, controls: pin.controls()) else {
            super.scrollWheel(with: event)
            return
        }
        let precise = event.hasPreciseScrollingDeltas
        switch target {
        case .zoom:
            let steps = zoomWheel.feed(delta: event.scrollingDeltaY, precise: precise, time: event.timestamp)
            if steps != 0 {
                pin.zoom(steps: steps, at: CaptureSession.globalMouseLocation())
            }
        case .opacity:
            let steps = opacityWheel.feed(delta: event.scrollingDeltaY, precise: precise, time: event.timestamp)
            if steps != 0 {
                pin.stepOpacity(steps)
            }
        }
    }

    private enum Target {
        case zoom
        case opacity
    }

    /// 按下的修饰键对应调什么；两个设置成同一个键时缩放优先
    private static func target(for flags: NSEvent.ModifierFlags, controls: PinControls) -> Target? {
        let pressed = flags.intersection([.command, .control, .option, .shift])
        if pressed == controls.zoomModifier.flags {
            return .zoom
        }
        if pressed == controls.opacityModifier.flags {
            return .opacity
        }
        return nil
    }

    /// 触控板双指缩放
    override func magnify(with event: NSEvent) {
        window_?.zoom(by: 1 + event.magnification, at: CaptureSession.globalMouseLocation())
    }

    // MARK: 键盘

    override func keyDown(with event: NSEvent) {
        guard let pin = window_ else { return }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if handleStepKey(event, modifiers: modifiers, pin: pin) {
            return
        }
        switch (key, modifiers) {
        case ("c", .command): pin.perform(.copy)
        case ("s", .command): pin.perform(.save)
        case ("w", .command): pin.perform(.close)
        case ("r", []): pin.apply { $0.rotate(clockwise: true) }
        case ("r", .shift): pin.apply { $0.rotate(clockwise: false) }
        case ("e", []): pin.perform(.edit)
        default:
            if event.keyCode == 53 {
                pin.perform(.close)
            } else if modifiers.isEmpty, let digit = Int(key), let opacity = PinState.opacity(forDigit: digit) {
                pin.setOpacity(opacity)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    /// 修饰键 + - / =：缩放或透明度，每次 5%（按物理键位，24 是 =，27 是 -）
    private func handleStepKey(_ event: NSEvent, modifiers: NSEvent.ModifierFlags, pin: PinWindow) -> Bool {
        guard event.keyCode == 24 || event.keyCode == 27,
              let target = Self.target(for: modifiers, controls: pin.controls()) else { return false }
        let steps = event.keyCode == 24 ? 1 : -1
        switch target {
        case .zoom: pin.zoom(steps: steps, at: CaptureSession.globalMouseLocation())
        case .opacity: pin.stepOpacity(steps)
        }
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.isKeyWindow == true, event.modifierFlags.contains(.command) else { return false }
        keyDown(with: event)
        return true
    }
}

/// 贴图的右键菜单（spec 3.3）
@MainActor
enum PinMenu {
    static func make(for pin: PinWindow) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        func item(_ title: String, _ key: String = "", action: @escaping () -> Void) {
            menu.addItem(ClosureMenuItem.make(title: title, keyEquivalent: key, action: action))
        }
        item("复制", "c") { pin.perform(.copy) }
        item("保存…", "s") { pin.perform(.save) }
        item("编辑标注", "e") { pin.perform(.edit) }
        item("识别文字") { pin.perform(.ocr) }
        item("翻译") { pin.perform(.translate) }
        menu.addItem(.separator())
        item("顺时针旋转", "r") { pin.apply { $0.rotate(clockwise: true) } }
        item("逆时针旋转") { pin.apply { $0.rotate(clockwise: false) } }
        item("恢复原始大小") { pin.apply { $0.zoom = 1 } }
        let opacity = NSMenu()
        for percent in stride(from: 100, through: 20, by: -20) {
            let entry = ClosureMenuItem.make(title: "\(percent)%", keyEquivalent: "") {
                pin.setOpacity(CGFloat(percent) / 100)
            }
            entry.state = Int((pin.state.opacity * 100).rounded()) == percent ? .on : .off
            opacity.addItem(entry)
        }
        let opacityItem = NSMenuItem(title: "透明度", action: nil, keyEquivalent: "")
        opacityItem.submenu = opacity
        menu.addItem(opacityItem)
        let shadow = ClosureMenuItem.make(title: "阴影", keyEquivalent: "") { pin.apply { $0.showsShadow.toggle() } }
        shadow.state = pin.state.showsShadow ? .on : .off
        menu.addItem(shadow)
        menu.addItem(.separator())
        item("关闭", "w") { pin.perform(.close) }
        item("关闭全部贴图") { pin.perform(.closeAll) }
        return menu
    }
}

/// 用闭包响应的菜单项。target 是弱引用，所以把动作对象同时放进 representedObject 保持住
@MainActor
enum ClosureMenuItem {
    static func make(title: String, keyEquivalent: String, action handler: @escaping () -> Void) -> NSMenuItem {
        let action = MenuAction(handler)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: keyEquivalent)
        item.target = action
        item.representedObject = action
        return item
    }
}

private final class MenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run() {
        handler()
    }
}

extension PinModifier {
    var flags: NSEvent.ModifierFlags {
        switch self {
        case .none: []
        case .command: .command
        case .control: .control
        case .option: .option
        case .shift: .shift
        }
    }
}
