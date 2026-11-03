import AppKit

/// 文字标注的排版和绘制。测量（`size(of:)`）和绘制用同一套属性，保证包围盒准确。
enum TextRendering {
    static let padding = CGSize(width: 6, height: 3)

    static func font(size: CGFloat, bold: Bool) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    static func attributes(_ box: TextBox, color: NSColor) -> [NSAttributedString.Key: Any] {
        [.font: font(size: box.fontSize, bold: box.bold), .foregroundColor: color]
    }

    /// 文字框的大小（含内边距）
    static func size(of box: TextBox) -> CGSize {
        let text = box.string.isEmpty ? " " : box.string
        let bounds = NSAttributedString(string: text, attributes: attributes(box, color: .black)).boundingRect(
            with: CGSize(width: 10000, height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading],
        )
        return CGSize(width: ceil(bounds.width) + padding.width * 2, height: ceil(bounds.height) + padding.height * 2)
    }

    /// context 已经是左上角原点的坐标系
    static func draw(_ box: TextBox, color: AnnotationColor, in context: CGContext) {
        // 总是按当前样式重新测量，字号、粗体改了之后底色块大小也跟着变
        let frame = CGRect(origin: box.origin, size: size(of: box))
        let textOrigin = CGPoint(x: frame.minX + padding.width, y: frame.minY + padding.height)
        withFlippedContext(context) {
            let fill = nsColor(color)
            switch box.decoration {
            case .plain:
                NSAttributedString(string: box.string, attributes: attributes(box, color: fill)).draw(at: textOrigin)
            case .outline:
                var outline = attributes(box, color: fill)
                outline[.strokeColor] = box.backgroundColor.map(nsColor) ?? contrasting(color)
                outline[.strokeWidth] = 12
                NSAttributedString(string: box.string, attributes: outline).draw(at: textOrigin)
                NSAttributedString(string: box.string, attributes: attributes(box, color: fill)).draw(at: textOrigin)
            case .background:
                // 旧数据没有背景色：色块用文字颜色，文字自动取黑或白
                let block = box.backgroundColor ?? color
                let text = box.backgroundColor == nil ? contrasting(color) : fill
                context.setFillColor(AnnotationRenderer.cgColor(block))
                context.addPath(CGPath(roundedRect: frame, cornerWidth: 4, cornerHeight: 4, transform: nil))
                context.fillPath()
                NSAttributedString(string: box.string, attributes: attributes(box, color: text)).draw(at: textOrigin)
            }
        }
    }

    static func drawCentered(_ text: String, in rect: CGRect, fontSize: CGFloat, color: NSColor, context: CGContext) {
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold), .foregroundColor: color,
        ])
        let size = string.size()
        withFlippedContext(context) {
            string.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        }
    }

    /// 浅色上用黑字，深色上用白字
    static func contrasting(_ color: AnnotationColor) -> NSColor {
        let luminance = 0.299 * color.red + 0.587 * color.green + 0.114 * color.blue
        return luminance > 0.65 ? .black : .white
    }

    static func nsColor(_ color: AnnotationColor) -> NSColor {
        NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    /// AppKit 画文字要用 NSGraphicsContext；flipped 为 true 时文字在左上角原点的坐标系里是正的
    private static func withFlippedContext(_ context: CGContext, _ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        body()
        NSGraphicsContext.restoreGraphicsState()
    }
}
