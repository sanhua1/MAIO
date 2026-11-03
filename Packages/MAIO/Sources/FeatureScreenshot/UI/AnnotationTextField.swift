import AppKit

/// 在遮罩上原地输入文字（spec 4.2：支持中文输入法；⌘⏎、Esc 或点击别处结束）。
///
/// 输入框本身的文字是透明的，只负责光标、选中和输入法；看到的文字由标注图层按最终效果实时画出
/// （`previewBox`），所以输入时就能看到描边和底色，和结果完全一致。
@MainActor
final class AnnotationTextField: NSObject, NSTextViewDelegate {
    private(set) var editingID: UUID?
    private var box: TextBox?
    /// 文字颜色
    private(set) var color = AnnotationColor.red
    private weak var host: OverlayView?
    private let textView = CommitTextView(frame: .zero)
    /// 结束编辑（⌘⏎ / Esc）时回调
    var onCommit: () -> Void = {}
    /// 内容变化时回调（重画预览）
    var onChange: () -> Void = {}

    var isEditing: Bool {
        box != nil
    }

    /// 正在输入的文字（包括输入法正在组字的部分）
    var currentBox: TextBox? {
        guard var box else { return nil }
        box.string = textView.string
        box.size = TextRendering.size(of: box)
        return box
    }

    override init() {
        super.init()
        textView.isRichText = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = TextRendering.padding
        textView.textColor = .clear
        textView.delegate = self
        textView.onCommit = { [weak self] in self?.onCommit() }
    }

    func begin(_ box: TextBox, color: AnnotationColor, editing id: UUID?, in view: OverlayView) {
        editingID = id
        host = view
        textView.string = box.string
        view.addSubview(textView)
        restyle(box, color: color)
        view.window?.makeFirstResponder(textView)
        textView.selectAll(nil)
    }

    /// 修改样式，保留内容、光标和选中范围
    func restyle(_ newBox: TextBox, color newColor: AnnotationColor) {
        box = newBox
        color = newColor
        let nsColor = TextRendering.nsColor(newColor)
        let font = TextRendering.font(size: newBox.fontSize, bold: newBox.bold)
        textView.font = font
        textView.typingAttributes = [.font: font, .foregroundColor: NSColor.clear]
        textView.textStorage?.addAttributes(
            [.font: font, .foregroundColor: NSColor.clear],
            range: NSRange(location: 0, length: textView.textStorage?.length ?? 0),
        )
        textView.insertionPointColor = newBox.decoration == .background ? TextRendering.nsColor(newBox.backgroundColor
            .map { TextAppearance.automaticBackground(for: $0) } ?? newColor) : nsColor
        textView.markedTextAttributes = [.underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: nsColor]
        updateFrame()
        onChange()
    }

    /// 结束编辑，返回最终的文字框（已测量大小）和文字颜色
    func finish() -> (box: TextBox, color: AnnotationColor, id: UUID?)? {
        guard var box = currentBox else { return nil }
        if box.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            box.string = ""
        }
        let id = editingID
        self.box = nil
        editingID = nil
        textView.removeFromSuperview()
        host?.window?.makeFirstResponder(host)
        return (box, color, id)
    }

    func textDidChange(_: Notification) {
        updateFrame()
        onChange()
    }

    /// 左上角固定，随内容变大
    private func updateFrame() {
        guard let box = currentBox, let host else { return }
        let frame = CGRect(origin: box.origin, size: CGSize(width: max(box.size.width, 40), height: box.size.height))
        textView.frame = host.localRect(frame)
        textView.textContainer?.containerSize = CGSize(width: 10000, height: 10000)
    }
}

/// ⌘⏎ 或 Esc 结束编辑（输入法正在组字时 Esc 交给输入法）
final class CommitTextView: NSTextView {
    var onCommit: () -> Void = {}

    override func keyDown(with event: NSEvent) {
        let command = event.modifierFlags.contains(.command)
        if (event.keyCode == 36 && command) || (event.keyCode == 53 && !hasMarkedText()) {
            onCommit()
            return
        }
        super.keyDown(with: event)
    }
}
