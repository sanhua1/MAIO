import AppKit

/// 把截图状态画到每个显示器的遮罩上。
extension CaptureSession {
    func render() {
        for panel in panels {
            let view = panel.overlayView
            renderFrame(on: view)
            renderAnnotations(on: view)
            renderMagnifier(on: view)
        }
        placeToolbar()
    }

    /// 选区（或高亮的窗口、控件）、边框、手柄、尺寸标签
    private func renderFrame(on view: OverlayView) {
        let bounds = view.display.bounds
        let canvas = view.canvas
        let target: CGRect?
        let showsHandles: Bool
        if let selection = interaction.selection {
            target = bounds == interaction.bounds ? selection : nil
            showsHandles = !interaction.isCreating
        } else if let highlight, bounds.intersects(highlight) {
            target = highlight.intersection(bounds)
            showsHandles = false
        } else {
            target = nil
            showsHandles = false
        }
        guard let target else {
            canvas.render(hole: nil, border: nil, handles: [])
            canvas.renderSizeBadge(text: nil, frame: .zero)
            return
        }
        let local = view.localRect(target)
        // 重新编辑时选区固定，不显示手柄
        let handles = showsHandles && edit == nil ? SelectionHandle.allCases.map { $0.point(in: local) } : []
        canvas.render(hole: local, border: local, handles: handles)
        let scale = display(at: CGPoint(x: target.midX, y: target.midY))?.scale ?? 1
        let pixels = SelectionGeometry.pixelAligned(target, scale: scale)
        let text = edit.map { "\($0.source.image.width) × \($0.source.image.height)" }
            ?? "\(Int((pixels.width * scale).rounded())) × \(Int((pixels.height * scale).rounded()))"
        let size = BadgeLayer.size(for: text)
        let frame = OverlayLayout.sizeLabelFrame(size: size, selection: target, bounds: bounds)
        canvas.renderSizeBadge(text: text, frame: view.localRect(frame))
    }

    /// 标注（选区底图 + 对象）和选中对象的虚线框
    private func renderAnnotations(on view: OverlayView) {
        let canvas = view.canvas
        // 正在输入的文字：隐藏原来的那一份，换成实时预览
        let editingID = textField.isEditing ? textField.editingID : nil
        let items = editor.visibleItems.filter { editingID == nil || $0.id != editingID } + (textPreview.map { [$0] } ?? [])
        guard let selection = interaction.selection, view.display.bounds == interaction.bounds,
              let display = selectionDisplay, let source = currentSource, !items.isEmpty || edit != nil
        else {
            canvas.renderAnnotations(nil, frame: .zero)
            canvas.renderAnnotationSelection(outline: nil, handles: [])
            return
        }
        let aligned = edit == nil ? SelectionGeometry.pixelAligned(selection, scale: display.scale) : selection
        canvas.renderAnnotations(
            .init(items: items, selection: aligned, source: source, cache: effectCache),
            frame: view.localRect(aligned),
        )
        if let selected = editor.document.selected, !isDrawing, !textField.isEditing {
            canvas.renderAnnotationSelection(
                outline: view.localRect(selected.bounds),
                handles: selected.handles.map { view.localRect(CGRect(origin: $0.1, size: .zero)).origin },
            )
        } else {
            canvas.renderAnnotationSelection(outline: nil, handles: [])
        }
    }

    private var isDrawing: Bool {
        if case .drawing = editor.drag {
            return true
        }
        return false
    }

    /// 放大镜：没有选区时，或者正在拖动时显示
    private func renderMagnifier(on view: OverlayView) {
        let bounds = view.display.bounds
        // 开始标注后不再显示（spec 4.1）
        let visible = options.showMagnifier && edit == nil && bounds.contains(cursor) && editor.document.isEmpty
            && !editor.isDragging && (interaction.selection == nil || interaction.isDragging)
        guard visible, let display = display(at: cursor) else {
            view.canvas.renderMagnifier(nil, frame: .zero)
            return
        }
        let x = cursor.x - bounds.minX
        let y = cursor.y - bounds.minY
        let colorText = color.map { options.colorFormat.string($0) } ?? "-"
        let state = MagnifierLayer.State(
            pixelX: Int((x * display.scale).rounded(.down)),
            pixelY: Int((y * display.scale).rounded(.down)),
            lines: ["\(Int(x)), \(Int(y))", colorText, "C 复制 · ⇧ 切换"],
            color: color.map { CGColor(
                srgbRed: CGFloat($0.red) / 255, green: CGFloat($0.green) / 255, blue: CGFloat($0.blue) / 255, alpha: 1,
            ) },
        )
        let frame = OverlayLayout.magnifierFrame(size: MagnifierLayer.size, cursor: cursor, bounds: bounds)
        view.canvas.renderMagnifier(state, frame: view.localRect(frame))
    }

    /// 选区确定（不在拖动）时，工具栏放在选区所在显示器上
    private func placeToolbar() {
        guard let selection = interaction.selection, !interaction.isDragging, !editor.isDragging,
              let view = panels.first(where: { $0.overlayView.display.bounds == interaction.bounds })?.overlayView
        else {
            toolbar.isHidden = true
            if toolbarModel.hint != nil {
                clearToolbarHover()
            }
            return
        }
        if toolbar.superview !== view {
            toolbar.removeFromSuperview()
            view.addSubview(toolbar)
        }
        // 按"三行"的高度定位，第三行出现、消失时前两行不动（放在选区上方时，下面空出一行）
        let extra = CaptureToolbar.optionsRowHeight
        let hasOptions = toolbarModel.activeTool?.hasOptions == true
        let base = toolbarSize ?? {
            let measured = toolbar.fittingSize
            return CGSize(width: measured.width, height: measured.height - (hasOptions ? extra : 0))
        }()
        toolbarSize = base
        let full = CGSize(width: base.width, height: base.height + extra)
        let slot = OverlayLayout.toolbarFrame(size: full, selection: selection, bounds: view.display.bounds)
        let frame = CGRect(origin: slot.origin, size: CGSize(width: base.width, height: base.height + (hasOptions ? extra : 0)))
        toolbar.frame = view.localRect(frame)
        toolbar.isHidden = false
    }
}
