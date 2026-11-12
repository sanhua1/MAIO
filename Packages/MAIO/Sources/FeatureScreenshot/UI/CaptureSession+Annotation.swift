import AppKit
import MAIOKit

/// 工具栏命令、文字输入、工具栏状态同步。
extension CaptureSession {
    func perform(_ command: ToolbarCommand) {
        // 文字的样式命令：作用于"当前这段文字"（正在输入 > 选中 > 默认）
        if toolbarModel.activeTool == .text, let change = textChange(for: command) {
            changeText(change)
            return
        }
        if case let .textColorTarget(target) = command {
            editor.textColorTarget = target
            syncToolbar()
            return
        }
        if textField.isEditing {
            commitText()
        }
        if performFinal(command) {
            return
        }
        switch command {
        case let .tool(tool): editor.select(tool: tool)
        case let .color(color): editor.setColor(color)
        case let .size(value): editor.setSize(value)
        case let .options(change): editor.setOptions(change)
        case .undo: editor.document.undo()
        case .redo: editor.document.redo()
        default: break
        }
        syncToolbar()
        render()
        // 点工具栏后把键盘焦点还给遮罩
        if let view = toolbar.superview {
            view.window?.makeFirstResponder(view)
        }
    }

    /// 不改标注的命令：打开颜色面板、取消、保存、复制
    private func performFinal(_ command: ToolbarCommand) -> Bool {
        switch command {
        case .customColor: colorPanel.open(current: toolbarModel.paletteColor)
        case .cancel: finish(.cancelled)
        case .save: confirm(.save)
        case .pin: confirm(.pin)
        case .copy: confirm(.copy)
        case .ocr: confirm(.ocr)
        case .translate: confirm(.translate)
        case .scrolling: confirm(.scrolling)
        case .record: confirm(.record)
        default: return false
        }
        return true
    }

    private func textChange(for command: ToolbarCommand) -> TextChange? {
        switch command {
        case let .color(color): .color(color)
        case let .size(value): .fontSize(CGFloat(value))
        case .textBold: .toggleBold
        case let .textDecoration(decoration): .decoration(decoration)
        default: nil
        }
    }

    // MARK: 文字样式

    /// 当前这段文字的样式：正在输入的 > 选中的 > 下一次新建的
    var currentTextAppearance: TextAppearance {
        if let box = textField.currentBox {
            return TextAppearance(box: box, color: textField.color)
        }
        if let (annotation, box) = editor.selectedText {
            return TextAppearance(box: box, color: annotation.color)
        }
        return editor.defaultTextAppearance
    }

    func changeText(_ change: TextChange) {
        if let box = textField.currentBox {
            var appearance = TextAppearance(box: box, color: textField.color)
            appearance.apply(change, target: editor.textColorTarget)
            editor.remember(appearance)
            textField.restyle(appearance.applied(to: box), color: appearance.foreground)
        } else {
            editor.changeText(change, measure: TextRendering.size(of:))
        }
        syncToolbar()
        render()
    }

    func syncToolbar() {
        toolbarModel.tool = editor.tool
        toolbarModel.activeTool = textField.isEditing ? .text : editor.activeTool
        toolbarModel.style = editor.style
        toolbarModel.canUndo = editor.document.canUndo
        toolbarModel.canRedo = editor.document.canRedo
        toolbarModel.nextCounter = editor.document.nextCounterNumber
        if toolbarModel.activeTool == .text {
            let appearance = currentTextAppearance
            toolbarModel.text = appearance
            toolbarModel.textColorTarget = appearance.colorTarget(editor.textColorTarget)
            toolbarModel.paletteColor = appearance.paletteColor(editor.textColorTarget)
            toolbarModel.sizeValue = Double(appearance.fontSize)
            toolbarModel.sizeRange = AnnotationTool.text.sizeRange
        } else {
            toolbarModel.paletteColor = editor.paletteColor
            let tool = editor.activeTool ?? .rectangle
            toolbarModel.sizeValue = editor.selectedSize ?? editor.style.size(for: tool)
            toolbarModel.sizeRange = tool.sizeRange
        }
    }

    // MARK: 文字输入

    func beginText(_ box: TextBox, color: AnnotationColor, editing id: UUID?) {
        guard let view = panels.first(where: { $0.overlayView.display.bounds == interaction.bounds })?.overlayView
        else { return }
        textField.begin(box, color: color, editing: id, in: view)
        syncToolbar()
        render()
    }

    func editText(_ id: UUID) {
        guard let annotation = editor.document.items.first(where: { $0.id == id }),
              case let .text(box) = annotation.shape else { return }
        beginText(box, color: annotation.color, editing: id)
    }

    func commitText() {
        guard let (box, color, id) = textField.finish() else { return }
        editor.commitText(box, color: color, editing: id)
        syncToolbar()
    }

    /// 正在输入的文字按最终效果画出来（输入框本身是透明的）
    var textPreview: Annotation? {
        guard let box = textField.currentBox, !box.string.isEmpty else { return nil }
        return Annotation(id: textField.editingID ?? Self.previewID, shape: .text(box), color: textField.color, lineWidth: 0)
    }

    static let previewID = UUID()
}
