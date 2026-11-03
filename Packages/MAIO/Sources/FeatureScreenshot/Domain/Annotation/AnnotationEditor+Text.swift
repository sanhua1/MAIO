import CoreGraphics
import Foundation

/// 文字的样式和提交。规则见 TextAppearance。
extension AnnotationEditor {
    /// 下一次新建文字使用的样式
    var defaultTextAppearance: TextAppearance {
        TextAppearance(
            foreground: style.color, background: style.textBackgroundColor, decoration: style.textDecoration,
            bold: style.bold, fontSize: CGFloat(style.size(for: .text)),
        )
    }

    /// 选中的文字
    var selectedText: (annotation: Annotation, box: TextBox)? {
        guard let selected = document.selected, case let .text(box) = selected.shape else { return nil }
        return (selected, box)
    }

    /// 把样式记成默认样式（下一次新建文字使用）
    mutating func remember(_ appearance: TextAppearance) {
        style.color = appearance.foreground
        style.textBackgroundColor = appearance.background
        style.textDecoration = appearance.decoration
        style.bold = appearance.bold
        style.setSize(Double(appearance.fontSize), for: .text)
    }

    /// 修改选中的文字；没有选中文字时修改默认样式。measure 用来重新测量文字框大小（需要 AppKit）
    mutating func changeText(_ change: TextChange, measure: (TextBox) -> CGSize) {
        guard let (annotation, box) = selectedText else {
            var appearance = defaultTextAppearance
            appearance.apply(change, target: textColorTarget)
            remember(appearance)
            return
        }
        var appearance = TextAppearance(box: box, color: annotation.color)
        appearance.apply(change, target: textColorTarget)
        remember(appearance)
        var updated = appearance.applied(to: box)
        updated.size = measure(updated)
        let key: String? = if case .fontSize = change {
            "size"
        } else {
            nil
        }
        updateSelected(coalescing: key) { item in
            item.color = appearance.foreground
            item.shape = .text(updated)
        }
    }

    /// 结束文字编辑：新增、修改，或者（文字为空时）删除。完成后选中这段文字，方便马上改样式
    mutating func commitText(_ box: TextBox, color: AnnotationColor, editing id: UUID?) {
        if let id, let existing = document.items.first(where: { $0.id == id }) {
            if box.string.isEmpty {
                document.remove(id: id)
                return
            }
            var updated = existing
            updated.shape = .text(box)
            updated.color = color
            document.selectedID = id
            guard updated != existing else { return }
            document.checkpoint()
            document.replace(updated)
            return
        }
        guard !box.string.isEmpty else { return }
        let annotation = Annotation(shape: .text(box), color: color, lineWidth: 0)
        document.add(annotation)
        document.selectedID = annotation.id
    }

    /// 新文字的文字框
    func newTextBox(at point: CGPoint) -> TextBox {
        defaultTextAppearance.applied(to: TextBox(
            origin: point, string: "", fontSize: 0, bold: false, decoration: .plain,
        ))
    }
}
