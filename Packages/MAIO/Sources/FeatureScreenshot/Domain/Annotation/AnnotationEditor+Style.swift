import CoreGraphics

/// 样式：颜色、大小档位、工具选项。都会同时作用于选中的对象。文字的样式见 +Text。
extension AnnotationEditor {
    /// 色板上高亮的颜色（文字的颜色由 TextAppearance 决定，不走这里）
    var paletteColor: AnnotationColor {
        document.selected?.color ?? style.color(for: activeTool ?? .rectangle)
    }

    mutating func setColor(_ color: AnnotationColor) {
        style.setColor(color, for: activeTool)
        updateSelected { annotation in
            guard annotation.tool.usesColor else { return }
            annotation.color = color
        }
    }

    /// 设置大小（连续可调）。连续调整同一个对象只算一步撤销
    mutating func setSize(_ value: Double) {
        guard let tool = activeTool else { return }
        style.setSize(value, for: tool)
        let size = CGFloat(style.size(for: tool))
        updateSelected(coalescing: "size") { annotation in
            switch annotation.shape {
            case .text: break // 文字走 changeText
            case let .mosaic(frame, _): annotation.shape = .mosaic(frame, blockSize: size)
            case let .blur(frame, _): annotation.shape = .blur(frame, radius: size)
            case let .counter(center, number, _): annotation.shape = .counter(center: center, number: number, radius: size)
            default: annotation.lineWidth = size
            }
        }
    }

    /// 修改工具选项（实心、圆角、虚线），同时作用于选中的对象
    mutating func setOptions(_ change: (inout ToolStyle) -> Void) {
        change(&style)
        let style = style
        updateSelected { annotation in
            switch annotation.shape {
            case let .rectangle(frame, _, _):
                annotation.shape = .rectangle(frame, filled: style.filled, rounded: style.rounded)
            case let .ellipse(frame, _): annotation.shape = .ellipse(frame, filled: style.filled)
            case let .line(from, to, _): annotation.shape = .line(from: from, to: to, dashed: style.dashed)
            default: break
            }
        }
    }
}

extension AnnotationEditor {
    /// 选中对象自己的大小（工具栏显示它，而不是默认值）
    var selectedSize: Double? {
        guard let selected = document.selected else { return nil }
        return switch selected.shape {
        case let .text(box): Double(box.fontSize)
        case let .mosaic(_, block): Double(block)
        case let .blur(_, radius): Double(radius)
        case let .counter(_, _, radius): Double(radius)
        default: Double(selected.lineWidth)
        }
    }
}
