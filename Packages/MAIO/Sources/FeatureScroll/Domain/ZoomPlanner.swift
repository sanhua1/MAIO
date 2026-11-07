import MAIOKit

/// 按住哪个修饰键时，滚轮变成缩放
enum ZoomModifier: String, Codable, CaseIterable, Sendable {
    case command, option, control

    var modifiers: KeyModifiers {
        switch self {
        case .command: .command
        case .option: .option
        case .control: .control
        }
    }

    var title: String {
        switch self {
        case .command: "⌘ Command"
        case .option: "⌥ Option"
        case .control: "⌃ Control"
        }
    }
}

/// 滚轮缩放的配置快照
struct ZoomConfig: Sendable, Equatable {
    var enabled: Bool
    var modifier: ZoomModifier
    var speed: Double
    var reversed: Bool
    /// 在这些 App 里不缩放，修饰键 + 滚轮照常交给 App。
    /// 始终包含 MAIO 自己：贴图的 ⌘ + 滚轮是调透明度
    var excludedBundleIDs: Set<String> = []
}

/// 修饰键 + 滚轮 → 触控板捏合缩放（ADR-0015）。纯函数，可单测。
enum ZoomPlanner {
    // 参考：references/LinearMouse/LinearMouse/EventTransformer/ModifierActionsTransformer.swift（MIT）
    /// 一格滚轮的缩放量（速度 1.0 时约 5%）
    static let magnificationPerNotch = 0.05
    /// 连续滚动的滚轮（罗技等）按像素算：约 10 像素一格
    static let magnificationPerPixel = magnificationPerNotch / 10

    /// 这个滚轮事件要变成多少缩放量；nil 表示不是缩放，照常滚动。
    /// reverseVertical：用户是否反转了纵向滚动（系统开着自然滚动时）。按反转后的方向算，
    /// 这样"往前拨滚轮 = 放大"不受自然滚动设置影响。
    static func magnification(
        _ event: PointerEvent,
        _ environment: RealtimeEnvironment,
        _ config: ZoomConfig,
        reverseVertical: Bool,
    ) -> Double? {
        guard config.enabled, !event.isSynthetic, event.device == .wheel,
              environment.modifiers.contains(config.modifier.modifiers) else { return nil }
        if let target = environment.targetBundleID, config.excludedBundleIDs.contains(target) {
            return nil
        }
        let raw = event.pixelY != 0 ? event.pixelY : event.scrollY
        guard raw != 0 else { return nil }
        var direction = reverseVertical ? -1.0 : 1.0
        if config.reversed {
            direction = -direction
        }
        return notches(event) * magnificationPerNotch * config.speed * direction
    }

    /// 这个事件算几格（带方向）。普通滚轮每个事件就是一格：事件里的像素量被系统的滚轮加速放大过
    /// （慢拨一格约 10 像素，快拨能到上百），按像素算会越拨越快、停不准，所以只看方向。
    /// 连续滚动的滚轮按像素折算，同样每个事件最多算一格。
    static func notches(_ event: PointerEvent) -> Double {
        let raw = event.pixelY != 0 ? event.pixelY : event.scrollY * 10
        let sign: Double = raw < 0 ? -1 : 1
        guard event.isContinuous else { return sign }
        return sign * min(abs(raw) * magnificationPerPixel / magnificationPerNotch, 1)
    }
}

/// 把每格滚轮的缩放量分摊到后面几帧，缩放过程是连续的而不是一跳一跳。
/// 每帧发出剩余量的一部分，所有帧加起来正好等于输入的总量。
struct ZoomEaser: Equatable {
    /// 每帧发出剩余量的比例
    static let fraction = 0.3
    /// 剩余量小于这个值时一次发完
    static let minimum = 0.0005

    private(set) var pending = 0.0

    mutating func add(_ magnification: Double) {
        pending += magnification
    }

    /// 这一帧要发的缩放量；没有剩余时返回 nil
    mutating func next() -> Double? {
        guard pending != 0 else { return nil }
        let step = abs(pending) <= Self.minimum ? pending : pending * Self.fraction
        pending -= step
        if abs(pending) < 1e-12 {
            pending = 0
        }
        return step
    }

    mutating func reset() {
        pending = 0
    }
}
