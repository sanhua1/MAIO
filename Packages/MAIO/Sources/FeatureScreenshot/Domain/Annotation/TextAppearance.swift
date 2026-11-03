import CoreGraphics

/// 一段文字的全部样式。工具栏永远显示并修改"当前这段文字"的样式：
/// 正在输入的 > 选中的 > 下一次新建的（默认样式）。修改时同时记成默认样式。
struct TextAppearance: Equatable, Sendable {
    /// 文字颜色
    var foreground: AnnotationColor
    /// 描边 / 底色的颜色（外观为"无"时不使用，但保留，切回描边时还是原来的颜色）
    var background: AnnotationColor
    var decoration: TextDecoration
    var bold: Bool
    var fontSize: CGFloat

    init(foreground: AnnotationColor, background: AnnotationColor, decoration: TextDecoration, bold: Bool, fontSize: CGFloat) {
        self.foreground = foreground
        self.background = background
        self.decoration = decoration
        self.bold = bold
        self.fontSize = fontSize
    }

    /// 从已有的文字读出样式。旧数据没有背景色时，按渲染时的效果（文字颜色取反的黑或白）补上
    init(box: TextBox, color: AnnotationColor) {
        self.init(
            foreground: color,
            background: box.backgroundColor ?? Self.automaticBackground(for: color),
            decoration: box.decoration, bold: box.bold, fontSize: box.fontSize,
        )
    }

    /// 色板改的是哪种颜色：外观为"无"时只有文字颜色
    func colorTarget(_ preferred: TextColorTarget) -> TextColorTarget {
        decoration == .plain ? .foreground : preferred
    }

    /// 色板上高亮的颜色
    func paletteColor(_ preferred: TextColorTarget) -> AnnotationColor {
        colorTarget(preferred) == .background ? background : foreground
    }

    mutating func apply(_ change: TextChange, target preferred: TextColorTarget) {
        switch change {
        case let .color(color):
            if colorTarget(preferred) == .background {
                background = color
            } else {
                foreground = color
            }
        case let .fontSize(size): fontSize = CGFloat(AnnotationTool.text.clampedSize(Double(size)))
        case .toggleBold: bold.toggle()
        case let .decoration(value): decoration = value
        }
    }

    /// 把样式写回文字框（内容和位置不变；大小需要调用方重新测量）
    func applied(to box: TextBox) -> TextBox {
        var copy = box
        copy.fontSize = fontSize
        copy.bold = bold
        copy.decoration = decoration
        copy.backgroundColor = background
        return copy
    }

    /// 浅色文字配黑色，深色文字配白色（和旧版渲染一致）
    static func automaticBackground(for color: AnnotationColor) -> AnnotationColor {
        let luminance = 0.299 * color.red + 0.587 * color.green + 0.114 * color.blue
        return luminance > 0.65 ? .black : .white
    }
}

/// 对文字样式的一次修改
enum TextChange: Equatable, Sendable {
    case color(AnnotationColor)
    case fontSize(CGFloat)
    case toggleBold
    case decoration(TextDecoration)
}
