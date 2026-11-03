/// 十种标注工具（spec 4.2）。
enum AnnotationTool: String, Codable, CaseIterable, Sendable {
    case rectangle, ellipse, arrow, line, pen, highlighter, text, mosaic, blur, counter

    var title: String {
        switch self {
        case .rectangle: "矩形"
        case .ellipse: "椭圆"
        case .arrow: "箭头"
        case .line: "直线"
        case .pen: "画笔"
        case .highlighter: "荧光笔"
        case .text: "文字"
        case .mosaic: "马赛克"
        case .blur: "模糊"
        case .counter: "序号"
        }
    }

    /// 截图时选择工具的按键（R O A L P H T M B N）
    var key: Character {
        switch self {
        case .rectangle: "r"
        case .ellipse: "o"
        case .arrow: "a"
        case .line: "l"
        case .pen: "p"
        case .highlighter: "h"
        case .text: "t"
        case .mosaic: "m"
        case .blur: "b"
        case .counter: "n"
        }
    }

    var symbol: String {
        switch self {
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .text: "textformat"
        case .mosaic: "checkerboard.rectangle"
        case .blur: "drop.halffull"
        case .counter: "1.circle"
        }
    }

    static func forKey(_ key: Character) -> AnnotationTool? {
        allCases.first { $0.key == key }
    }

    /// 大小的范围（连续可调，整数）：线宽、字号、马赛克块大小、模糊强度或序号半径，单位 pt
    var sizeRange: ClosedRange<Double> {
        switch self {
        case .rectangle, .ellipse, .arrow, .line, .pen: 1 ... 40
        case .highlighter: 4 ... 80
        case .text: 8 ... 160
        case .mosaic: 2 ... 60
        case .blur: 1 ... 50
        case .counter: 6 ... 60
        }
    }

    var defaultSize: Double {
        switch self {
        case .rectangle, .ellipse, .arrow, .line, .pen: 4
        case .highlighter: 16
        case .text: 18
        case .mosaic: 8
        case .blur: 8
        case .counter: 13
        }
    }

    /// 限制在范围内并取整
    func clampedSize(_ value: Double) -> Double {
        min(max(value.rounded(), sizeRange.lowerBound), sizeRange.upperBound)
    }

    /// 是否使用颜色（马赛克、模糊不用）
    var usesColor: Bool {
        self != .mosaic && self != .blur
    }
}

/// 文字工具里，色板改的是文字颜色还是背景色（描边 / 底色）
enum TextColorTarget: Sendable {
    case foreground
    case background
}

/// 记住的工具样式（保存在设置里，spec 4.2"上次用过的颜色和粗细会记住"）。
struct ToolStyle: Codable, Equatable, Sendable {
    var color = AnnotationColor.red
    /// 荧光笔单独记颜色，默认黄色
    var highlighterColor = AnnotationColor.yellow
    /// 每个工具的大小（pt），键是工具的 rawValue。旧版本的 sizeLevels（四档）不再使用
    var sizes: [String: Double] = [:]
    var filled = false
    var rounded = false
    var dashed = false
    var bold = false
    var textDecoration = TextDecoration.plain
    /// 文字描边 / 底色的颜色
    var textBackgroundColor = AnnotationColor.white

    func size(for tool: AnnotationTool) -> Double {
        tool.clampedSize(sizes[tool.rawValue] ?? tool.defaultSize)
    }

    mutating func setSize(_ value: Double, for tool: AnnotationTool) {
        sizes[tool.rawValue] = tool.clampedSize(value)
    }

    func color(for tool: AnnotationTool) -> AnnotationColor {
        tool == .highlighter ? highlighterColor : color
    }

    mutating func setColor(_ value: AnnotationColor, for tool: AnnotationTool?) {
        if tool == .highlighter {
            highlighterColor = value
        } else {
            color = value
        }
    }
}
