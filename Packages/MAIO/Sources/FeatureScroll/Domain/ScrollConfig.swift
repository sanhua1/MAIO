import MAIOKit

/// 实时线程使用的不可变配置快照（由 ScrollSettings 生成）。
struct ScrollConfig: Sendable, Equatable {
    struct Rules: Sendable, Equatable {
        var reverseVertical: Bool
        var reverseHorizontal: Bool
        var smoothVertical: Bool
        var smoothHorizontal: Bool
    }

    var rules: Rules
    var exceptions: [String: AppException]
    var step: Double
    var speed: Double
    var shiftToHorizontal: Bool
    var animation: SmoothScroller.Parameters
    var zoom: ZoomConfig

    /// ownBundleID：MAIO 自己的 bundle ID，鼠标在 MAIO 的窗口（贴图等）上时不缩放
    init(settings: ScrollSettings, framesPerSecond: Double, ownBundleID: String? = nil) {
        rules = Rules(
            reverseVertical: settings.reverseVertical,
            reverseHorizontal: settings.reverseHorizontal,
            smoothVertical: settings.smoothEnabled && settings.smoothVertical,
            smoothHorizontal: settings.smoothEnabled && settings.smoothHorizontal,
        )
        exceptions = Dictionary(settings.exceptions.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
        step = settings.step
        speed = settings.speed
        shiftToHorizontal = settings.shiftToHorizontal
        animation = SmoothScroller.Parameters(duration: settings.duration, framesPerSecond: framesPerSecond)
        zoom = ZoomConfig(
            enabled: settings.zoomEnabled,
            modifier: settings.zoomModifier,
            speed: settings.zoomSpeed,
            reversed: settings.zoomReversed,
            excludedBundleIDs: Set([ownBundleID].compactMap(\.self)),
        )
    }

    /// 套用 App 例外后的规则。
    func rules(for bundleID: String?) -> Rules {
        guard let bundleID, let exception = exceptions[bundleID] else { return rules }
        var result = rules
        if exception.disableSmooth {
            result.smoothVertical = false
            result.smoothHorizontal = false
        }
        if exception.disableReverse {
            result.reverseVertical = false
            result.reverseHorizontal = false
        }
        return result
    }
}
