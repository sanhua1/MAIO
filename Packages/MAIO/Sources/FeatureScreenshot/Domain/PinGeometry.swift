import CoreGraphics

/// 贴图的缩放、旋转、透明度（spec 3.3）。
struct PinState: Equatable, Sendable {
    static let zoomRange: ClosedRange<CGFloat> = 0.1 ... 5
    static let opacityRange: ClosedRange<CGFloat> = 0.1 ... 1
    /// 阴影留出的外边距（pt）
    static let margin: CGFloat = 14

    /// 原始大小（pt，未旋转）
    var imageSize: CGSize
    var zoom: CGFloat = 1
    /// 顺时针旋转的 90° 次数（0～3）
    var quarterTurns = 0
    var opacity: CGFloat = 1
    var showsShadow = true

    /// 旋转、缩放后的内容大小
    var contentSize: CGSize {
        let size = quarterTurns.isMultiple(of: 2) ? imageSize : CGSize(width: imageSize.height, height: imageSize.width)
        return CGSize(width: (size.width * zoom).rounded(), height: (size.height * zoom).rounded())
    }

    /// 窗口大小（内容 + 四周外边距）
    var windowSize: CGSize {
        CGSize(width: contentSize.width + Self.margin * 2, height: contentSize.height + Self.margin * 2)
    }

    mutating func rotate(clockwise: Bool) {
        quarterTurns = (quarterTurns + (clockwise ? 1 : 3)) % 4
    }

    /// 滚轮、- = 每一步的缩放和透明度变化（用户要求 5%）
    static let step: CGFloat = 0.05

    /// 以 anchor（内容里的点，0～1 的相对位置）为中心缩放，返回新的内容左上角（全局坐标，左上角原点）
    mutating func zoom(by factor: CGFloat, anchor: CGPoint, contentOrigin: CGPoint) -> CGPoint {
        zoom(to: zoom * factor, anchor: anchor, contentOrigin: contentOrigin)
    }

    /// 按步缩放：每步 ±5 个百分点，并对齐到 5% 的整数倍（例如 100% → 105% → 110%）
    mutating func zoom(steps: Int, anchor: CGPoint, contentOrigin: CGPoint) -> CGPoint {
        let target = ((zoom / Self.step).rounded() + CGFloat(steps)) * Self.step
        return zoom(to: target, anchor: anchor, contentOrigin: contentOrigin)
    }

    mutating func zoom(to value: CGFloat, anchor: CGPoint, contentOrigin: CGPoint) -> CGPoint {
        let old = contentSize
        zoom = min(max(value, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        let new = contentSize
        return CGPoint(
            x: contentOrigin.x + (old.width - new.width) * anchor.x,
            y: contentOrigin.y + (old.height - new.height) * anchor.y,
        )
    }

    mutating func stepOpacity(_ steps: Int) {
        setOpacity(((opacity / Self.step).rounded() + CGFloat(steps)) * Self.step)
    }

    mutating func setOpacity(_ value: CGFloat) {
        opacity = min(max(value, Self.opacityRange.lowerBound), Self.opacityRange.upperBound)
    }

    /// 数字键：1～9 是 10%～90%，0 是 100%
    static func opacity(forDigit digit: Int) -> CGFloat? {
        guard (0 ... 9).contains(digit) else { return nil }
        return digit == 0 ? 1 : CGFloat(digit) / 10
    }
}

/// 贴图上调整缩放、透明度用的修饰键（配合滚轮或 - / = 键）
enum PinModifier: String, Codable, CaseIterable, Sendable {
    /// 不按修饰键，直接滚轮 / 直接按 - =
    case none
    case command
    case control
    case option
    case shift

    var title: String {
        switch self {
        case .none: "不按修饰键"
        case .command: "⌘"
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        }
    }
}

/// 贴图的操作设置
struct PinControls: Equatable, Sendable {
    var zoomModifier = PinModifier.none
    var opacityModifier = PinModifier.command
}
