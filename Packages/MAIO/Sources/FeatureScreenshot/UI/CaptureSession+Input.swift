import AppKit
import MAIOKit

/// 截图时的鼠标和键盘：先交给标注编辑，标注不处理的再交给选区。
extension CaptureSession {

    // MARK: 鼠标

    func overlayMouseDown(at point: CGPoint, clickCount: Int, display: DisplayInfo) {
        cursor = point
        // 正在输入文字时，点别处只结束输入
        if textField.isEditing {
            commitText()
            render()
            return
        }
        if annotationMouseDown(at: point, clickCount: clickCount, display: display) {
            syncToolbar()
            render()
            return
        }
        // 重新编辑时选区固定：只有双击选区（完成）有效
        if let edit {
            if clickCount >= 2, edit.rect.contains(point) {
                confirm(options.primaryAction)
            }
            return
        }
        // 已经有标注时不能重新框选（标注会落到选区外面）
        if !editor.document.isEmpty, let selection = interaction.selection, !selection.contains(point),
           SelectionGeometry.handle(at: point, in: selection) == nil {
            return
        }
        let effect = interaction.mouseDown(at: point, clickCount: clickCount, displayBounds: display.bounds)
        if effect == .confirm {
            confirm(options.primaryAction)
            return
        }
        if case .moving = interaction.drag {
            NSCursor.closedHand.set()
        }
        render()
    }

    /// 返回 true 表示标注处理了这次点击
    private func annotationMouseDown(at point: CGPoint, clickCount: Int, display: DisplayInfo) -> Bool {
        guard let selection = interaction.selection, display.bounds == interaction.bounds else { return false }
        // 选区的手柄优先（除非点在选中标注自己的手柄上）
        if editor.document.selected?.handle(at: point) == nil,
           SelectionGeometry.handle(at: point, in: selection) != nil {
            return false
        }
        switch editor.mouseDown(at: point, clickCount: clickCount, selection: selection) {
        case .notHandled:
            return false
        case .handled:
            return true
        case let .beginText(origin):
            beginText(editor.newTextBox(at: origin), color: editor.style.color(for: .text), editing: nil)
            return true
        case let .editText(id):
            editText(id)
            return true
        }
    }

    func overlayMouseDragged(to point: CGPoint) {
        cursor = point
        if editor.isDragging {
            editor.mouseDragged(to: point, constrained: NSEvent.modifierFlags.contains(.shift))
            render()
            return
        }
        interaction.mouseDragged(to: point)
        if interaction.selection != nil {
            highlight = nil
        }
        updateColor()
        render()
    }

    func overlayMouseUp(at point: CGPoint) {
        cursor = point
        if editor.isDragging {
            editor.mouseUp()
            syncToolbar()
            updateCursorShape()
            render()
            return
        }
        interaction.mouseUp(highlighted: highlight)
        if interaction.selection != nil {
            highlight = nil
        }
        updateCursorShape()
        render()
    }

    func overlayMouseMoved(to point: CGPoint) {
        cursor = point
        // 鼠标已经离开工具栏时兜底清掉提示（悬停回调有时会晚到）
        if !isOverToolbar(point) {
            clearToolbarHover()
        }
        updateColor()
        updateHover()
        updateCursorShape()
        render()
    }

    func overlayRightMouseDown() {
        cancelOneLevel()
    }

    /// 滚轮：序号工具调整下一个编号，其他工具（或选中的对象）调整大小，每步 1 pt
    func overlayScrollWheel(_ event: NSEvent) {
        guard let tool = textField.isEditing ? .text : editor.activeTool, !editor.isDragging else { return }
        let adjustsCounter = tool == .counter && editor.document.selected == nil
        let delta = event.scrollingDeltaY
        let precise = event.hasPreciseScrollingDeltas
        let step = adjustsCounter
            ? counterWheel.feed(delta: delta, precise: precise, time: event.timestamp)
            : sizeWheel.feed(delta: delta, precise: precise, time: event.timestamp)
        guard step != 0 else { return }
        if adjustsCounter {
            editor.adjustCounter(by: step)
            syncToolbar()
        } else {
            perform(.size(toolbarModel.sizeValue + Double(step)))
        }
    }

    // MARK: 键盘

    func overlayKeyDown(_ event: NSEvent) -> Bool {
        // 正在输入文字时，按键都交给文字框
        guard !textField.isEditing else { return false }
        shiftAlone = false
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if handleAnnotationKey(event.keyCode, modifiers: modifiers) {
            syncToolbar()
            updateCursorShape()
            render()
            return true
        }
        switch (event.keyCode, modifiers) {
        case (53, _): cancelOneLevel()
        case (36, []), (76, []): confirm(options.primaryAction)
        case (8, [.command]):
            if interaction.selection != nil {
                confirm(.copy)
            } else {
                copyColor()
            }
        case (8, []): copyColor()
        case (0, [.command]): selectWholeDisplay()
        case let (code, [.command]) where Self.outputShortcuts[code] != nil:
            if let action = Self.outputShortcuts[code] {
                confirm(action)
            }
        case (123 ... 126, []), (123 ... 126, [.shift]): nudge(keyCode: event.keyCode, resize: modifiers == .shift)
        default: return false
        }
        return true
    }

    /// 标注相关的按键：工具字母、撤销重做、删除选中对象、方向键移动选中对象
    /// ⌘S 保存、⌘P 贴图、⌘O 识别文字、⌘T 翻译、⌘L 长截图、⌘R 录屏（按物理键位）
    private static let outputShortcuts: [UInt16: CaptureAction] = [
        1: .save, 35: .pin, 31: .ocr, 17: .translate, 37: .scrolling, 15: .record,
    ]

    private func handleAnnotationKey(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard interaction.selection != nil, !interaction.isDragging, !editor.isDragging else { return false }
        switch (keyCode, modifiers) {
        case (6, [.command]):
            editor.document.undo()
        case (6, [.command, .shift]):
            editor.document.redo()
        case (51, []), (117, []):
            return editor.deleteSelected()
        case (123 ... 126, []) where editor.document.selected != nil:
            moveSelectedAnnotation(keyCode: keyCode)
        case (_, []):
            guard let tool = AnnotationTool.allCases.first(where: { KeyCodes.code(for: $0) == keyCode }) else {
                return false
            }
            editor.select(tool: tool)
        default:
            return false
        }
        return true
    }

    func overlayFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        let modifiers = flags.intersection([.command, .shift, .option, .control])
        // 单独按一下 ⇧（中间没有按别的键）切换颜色格式；正在画图时 ⇧ 是吸附，不切换
        if modifiers == .shift, !editor.isDragging {
            shiftAlone = true
        } else if modifiers.isEmpty, shiftAlone {
            shiftAlone = false
            options.colorFormat = options.colorFormat.next
            callbacks.colorFormatChanged(options.colorFormat)
            render()
        } else {
            shiftAlone = false
        }
        let command = modifiers.contains(.command)
        if command != commandHeld {
            commandHeld = command
            updateHover()
            render()
        }
    }

    // MARK: 选区

    /// Esc / 右键逐层退出（spec 3.2）：取消选中对象 → 取消工具 → 取消选区 → 退出截图。
    /// 已经有标注时，取消选区会丢掉标注，所以这一层改为直接退出前不取消选区（再按一次退出）。
    func cancelOneLevel() {
        if editor.escape() {
            syncToolbar()
            updateCursorShape()
            render()
            return
        }
        if edit != nil || !editor.document.isEmpty || interaction.cancel() == .exit {
            finish(.cancelled)
            return
        }
        updateHover()
        updateCursorShape()
        render()
    }

    private func selectWholeDisplay() {
        guard edit == nil, editor.document.isEmpty, let display = display(at: cursor) else { return }
        interaction.select(display.display.bounds, displayBounds: display.display.bounds)
        highlight = nil
        render()
    }

    private var pixelStep: CGFloat {
        1 / (selectionDisplay?.scale ?? 1)
    }

    private func nudge(keyCode: UInt16, resize: Bool) {
        guard edit == nil else { return }
        let (dx, dy) = Self.direction(keyCode, step: pixelStep)
        interaction.nudge(dx: dx, dy: dy, resize: resize)
        render()
    }

    private func moveSelectedAnnotation(keyCode: UInt16) {
        guard let selected = editor.document.selected else { return }
        let (dx, dy) = Self.direction(keyCode, step: pixelStep)
        editor.document.checkpoint()
        editor.document.replace(selected.moved(by: CGVector(dx: dx, dy: dy)))
    }

    private static func direction(_ keyCode: UInt16, step: CGFloat) -> (CGFloat, CGFloat) {
        switch keyCode {
        case 123: (-step, 0)
        case 124: (step, 0)
        case 125: (0, step)
        default: (0, -step)
        }
    }
}

extension KeyCodes {
    /// 工具字母对应的键码（按物理键位，不受输入法和键盘布局影响）
    static func code(for tool: AnnotationTool) -> UInt16? {
        code(named: String(tool.key))
    }
}
