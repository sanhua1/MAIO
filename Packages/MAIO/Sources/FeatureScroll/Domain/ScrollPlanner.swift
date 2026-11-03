import MAIOKit

/// 对单个滚轮事件的处理决定（纯函数，可单测）。
struct ScrollPlan: Equatable {
    /// 吞掉原始事件（两个方向都交给平滑滚动）
    var consume = false
    /// 放行时写回的值（行单位）
    var passY: Double
    var passX: Double
    /// 交给平滑滚动的位移（像素，已含步长与速度），0 表示该方向不平滑
    var smoothY = 0.0
    var smoothX = 0.0

    var hasSmoothing: Bool {
        smoothY != 0 || smoothX != 0
    }

    static func untouched(_ event: PointerEvent) -> ScrollPlan {
        ScrollPlan(passY: event.scrollY, passX: event.scrollX)
    }
}

/// 滚轮反转与平滑的决策。算法思路参考 Mos（references/Mos/Mos/ScrollCore/ScrollCore.swift），重新实现。
enum ScrollPlanner {
    /// 按住这些修饰键时不平滑：平滑滚动发出的合成事件不带修饰键，会破坏 ⌘/⌃ + 滚轮缩放等操作
    static let modifiersBlockingSmooth: KeyModifiers = [.command, .control, .option]

    static func plan(_ event: PointerEvent, _ environment: RealtimeEnvironment, _ config: ScrollConfig) -> ScrollPlan {
        // 触控板 / 妙控鼠标、MAIO 自己发出的事件：一律不碰
        guard !event.isSynthetic, event.device == .wheel,
              event.scrollY != 0 || event.scrollX != 0 else { return .untouched(event) }

        let rules = config.rules(for: environment.effectiveBundleID)
        // 按住 ⇧ 且只有纵向位移：这次滚动实际是横向的，按横向的偏好处理
        let shifted = config.shiftToHorizontal && environment.modifiers.contains(.shift)
            && event.scrollY != 0 && event.scrollX == 0
        let reverseY = shifted ? rules.reverseHorizontal : rules.reverseVertical
        var plan = ScrollPlan(
            passY: reverseY ? -event.scrollY : event.scrollY,
            passX: rules.reverseHorizontal ? -event.scrollX : event.scrollX,
        )

        // 已经是连续滚动（平滑滚动驱动、远程桌面）再平滑会"双重平滑"，只做反转
        let canSmooth = !event.isContinuous && environment.modifiers.isDisjoint(with: modifiersBlockingSmooth)
        let smoothY = canSmooth && event.scrollY != 0 && (shifted ? rules.smoothHorizontal : rules.smoothVertical)
        let smoothX = canSmooth && event.scrollX != 0 && rules.smoothHorizontal
        guard smoothY || smoothX else { return plan }

        if smoothY {
            let pixels = amplified(event.pixelY, line: event.scrollY, reversed: reverseY, config: config)
            // ⇧ 横向：合成事件不带 ⇧，需要自己把位移放到横向
            if shifted {
                plan.smoothX = pixels
            } else {
                plan.smoothY = pixels
            }
            plan.passY = 0
        }
        if smoothX {
            plan.smoothX += amplified(event.pixelX, line: event.scrollX, reversed: rules.reverseHorizontal, config: config)
            plan.passX = 0
        }
        plan.consume = plan.passY == 0 && plan.passX == 0
        return plan
    }

    /// 像素位移：不足步长时补到步长，再乘以速度。
    static func amplified(_ pixels: Double, line: Double, reversed: Bool, config: ScrollConfig) -> Double {
        let raw = pixels != 0 ? pixels : line * 10
        let sign: Double = (raw < 0) != reversed ? -1 : 1
        return sign * max(abs(raw), config.step) * config.speed
    }
}
