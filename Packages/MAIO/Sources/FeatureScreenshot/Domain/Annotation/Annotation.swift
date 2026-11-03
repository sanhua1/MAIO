import CoreGraphics
import Foundation

/// 标注颜色（sRGB，0～1）。
struct AnnotationColor: Codable, Equatable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    static let red = AnnotationColor(red: 0.93, green: 0.23, blue: 0.21)
    static let orange = AnnotationColor(red: 1, green: 0.58, blue: 0)
    static let yellow = AnnotationColor(red: 1, green: 0.84, blue: 0.04)
    static let green = AnnotationColor(red: 0.2, green: 0.78, blue: 0.35)
    static let blue = AnnotationColor(red: 0, green: 0.48, blue: 1)
    static let purple = AnnotationColor(red: 0.69, green: 0.32, blue: 0.87)
    static let black = AnnotationColor(red: 0, green: 0, blue: 0)
    static let white = AnnotationColor(red: 1, green: 1, blue: 1)

    /// 工具栏上的 8 个预设色
    static let presets: [AnnotationColor] = [.red, .orange, .yellow, .green, .blue, .purple, .black, .white]
}

/// 文字标注的外观（三者互斥）。文字颜色是标注的 color；描边和底色用 TextBox.backgroundColor。
enum TextDecoration: String, Codable, CaseIterable, Sendable {
    case plain
    /// 文字外面一圈描边，复杂背景上也看得清
    case outline
    /// 文字下面垫一个颜色块
    case background
}

/// 文字标注。`origin` 是左上角；`size` 由界面按字体测量后填入（Domain 不能 import AppKit）。
struct TextBox: Codable, Equatable, Sendable {
    var origin: CGPoint
    var string: String
    var fontSize: CGFloat
    var bold: Bool
    var decoration: TextDecoration
    /// 描边或底色的颜色。旧数据没有这个字段时按文字颜色自动取黑或白
    var backgroundColor: AnnotationColor?
    var size: CGSize = .zero

    var frame: CGRect {
        CGRect(origin: origin, size: size)
    }
}

/// 标注的形状。坐标单位是 pt；截图过程中用全局坐标，存入历史时换成相对截图左上角的坐标。
enum AnnotationShape: Codable, Equatable, Sendable {
    case rectangle(CGRect, filled: Bool, rounded: Bool)
    case ellipse(CGRect, filled: Bool)
    case arrow(from: CGPoint, to: CGPoint)
    case line(from: CGPoint, to: CGPoint, dashed: Bool)
    case pen([CGPoint])
    case highlighter([CGPoint])
    case text(TextBox)
    /// 马赛克：不可逆，每块取平均色（spec 4.2）
    case mosaic(CGRect, blockSize: CGFloat)
    case blur(CGRect, radius: CGFloat)
    case counter(center: CGPoint, number: Int, radius: CGFloat)
}

/// 一个可以再次选中、移动、修改的标注对象。
struct Annotation: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var shape: AnnotationShape
    var color: AnnotationColor
    var lineWidth: CGFloat

    /// 平移并缩放（存入历史时把全局坐标换成图片坐标）
    func transformed(offset: CGVector, scale: CGFloat) -> Annotation {
        var copy = self
        copy.lineWidth = lineWidth * scale
        func point(_ value: CGPoint) -> CGPoint {
            CGPoint(x: (value.x + offset.dx) * scale, y: (value.y + offset.dy) * scale)
        }
        func rect(_ value: CGRect) -> CGRect {
            CGRect(origin: point(value.origin), size: CGSize(width: value.width * scale, height: value.height * scale))
        }
        copy.shape = switch shape {
        case let .rectangle(frame, filled, rounded): .rectangle(rect(frame), filled: filled, rounded: rounded)
        case let .ellipse(frame, filled): .ellipse(rect(frame), filled: filled)
        case let .arrow(from, to): .arrow(from: point(from), to: point(to))
        case let .line(from, to, dashed): .line(from: point(from), to: point(to), dashed: dashed)
        case let .pen(points): .pen(points.map(point))
        case let .highlighter(points): .highlighter(points.map(point))
        case let .text(box):
            .text(TextBox(
                origin: point(box.origin), string: box.string, fontSize: box.fontSize * scale, bold: box.bold,
                decoration: box.decoration, backgroundColor: box.backgroundColor, size: CGSize(
                    width: box.size.width * scale,
                    height: box.size.height * scale,
                ),
            ))
        case let .mosaic(frame, block): .mosaic(rect(frame), blockSize: block * scale)
        case let .blur(frame, radius): .blur(rect(frame), radius: radius * scale)
        case let .counter(center, number, radius): .counter(center: point(center), number: number, radius: radius * scale)
        }
        return copy
    }
}
