/// 按系统的手感步进亮度、音量（纯逻辑）：
/// 每按一下走 1/16（系统浮窗的一格）；⌥⇧ 一起按住时走 1/64（四分之一格）。
/// 先对齐到格子上再走，和系统一样：从 40% 往上按，先到 43.75%（第 7 格），而不是 46.25%。
enum LevelStepper {
    static let coarseSteps = 16
    static let fineSteps = 64

    static func step(_ value: VCPValue, up: Bool, fine: Bool) -> Int {
        let steps = fine ? fineSteps : coarseSteps
        let position = Double(value.current) / Double(value.maximum) * Double(steps)
        // 显示器只接受整数：格点 6.25 写下去读回来是 6。把 ±半个单位内的值都当成正好在格点上，否则会卡在原地
        let tolerance = 0.5 / Double(value.maximum) * Double(steps)
        let target = up ? (position + tolerance).rounded(.down) + 1 : (position - tolerance).rounded(.up) - 1
        let clamped = min(max(target, 0), Double(steps))
        return Int((clamped / Double(steps) * Double(value.maximum)).rounded())
    }
}

/// 显示器音量与静音。很多显示器不支持 DDC 静音（0x8D），这里统一用"音量设成 0、记住原来的值"实现。
struct VolumeState: Sendable, Hashable {
    var value: VCPValue
    /// 静音前的音量；不为 nil 表示处于静音
    private(set) var savedBeforeMute: Int?

    init(value: VCPValue) {
        self.value = value
    }

    var isMuted: Bool {
        savedBeforeMute != nil
    }

    /// 音量加减。静音时按加减先恢复原音量再走一步（和系统一样）。返回要写给显示器的值
    mutating func step(up: Bool, fine: Bool) -> Int {
        if let saved = savedBeforeMute {
            value.current = saved
            savedBeforeMute = nil
        }
        value.current = LevelStepper.step(value, up: up, fine: fine)
        return value.current
    }

    /// 直接设成某个值（菜单里拖音量条），同时取消静音
    mutating func set(_ current: Int) {
        savedBeforeMute = nil
        value.current = min(max(current, 0), value.maximum)
    }

    /// 切换静音。返回要写给显示器的值
    mutating func toggleMute() -> Int {
        if let saved = savedBeforeMute {
            value.current = saved
            savedBeforeMute = nil
        } else {
            // 已经是 0 时静音没有意义，取消静音时恢复到一格
            savedBeforeMute = value.current > 0 ? value.current : value.maximum / LevelStepper.coarseSteps
            value.current = 0
        }
        return value.current
    }

    /// 从显示器重新读到的值（用户可能用显示器自己的按钮调过）。读到非 0 说明已经不是静音
    mutating func sync(_ fresh: VCPValue) {
        if isMuted, fresh.current == 0 {
            value.maximum = fresh.maximum
            return
        }
        savedBeforeMute = nil
        value = fresh
    }
}
