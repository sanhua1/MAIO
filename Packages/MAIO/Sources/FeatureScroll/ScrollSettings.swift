import MAIOKit

/// 滚动设置。默认值与 Mos 一致（references/Mos/Mos/Utils/Constants.swift 中的 OPTIONS_SCROLL_DEFAULT）。
/// 字段只增不删；结构不兼容的修改要提升 schemaVersion 并实现 migrate。
struct ScrollSettings: FeatureSettings {
    static let defaultValue = ScrollSettings()

    /// 反转鼠标纵向滚动（系统开着"自然滚动"时，打开这项让鼠标恢复传统方向，触控板不受影响）
    var reverseVertical = true
    var reverseHorizontal = true

    var smoothEnabled = true
    var smoothVertical = true
    var smoothHorizontal = true
    /// 每格滚轮的最小位移（像素）
    var step = 33.6
    /// 位移倍率
    var speed = 2.7
    /// 平滑持续时间（1–5，越大停得越慢）
    var duration = 4.35

    /// 按住 ⇧ 时把纵向滚动转为横向
    var shiftToHorizontal = true

    /// 按住修饰键 + 滚轮：模拟触控板双指捏合缩放（ADR-0015）
    var zoomEnabled = true
    var zoomModifier: ZoomModifier = .command
    var zoomSpeed = 1.0
    /// 反转缩放方向（默认往前拨滚轮放大）
    var zoomReversed = false

    var exceptions: [AppException] = []

    static let stepRange = 10.0 ... 100.0
    static let speedRange = 1.0 ... 8.0
    static let durationRange = 1.0 ... 5.0
    static let zoomSpeedRange = 0.3 ... 3.0
}

/// 按 App 的例外规则（以鼠标所指的 App 为准）。
struct AppException: Codable, Sendable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var disableSmooth = true
    var disableReverse = false

    var id: String {
        bundleID
    }
}
