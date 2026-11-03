import CoreGraphics
import MAIOKit

/// 当前实际按住的修饰键（直接问系统，不依赖事件）。
/// 用于两种情况：会话开始前用户就松手了；以及"松开"事件丢失时的兜底检查。
enum ModifierState {
    static var current: KeyModifiers {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        var result: KeyModifiers = []
        if flags.contains(.maskCommand) {
            result.insert(.command)
        }
        if flags.contains(.maskShift) {
            result.insert(.shift)
        }
        if flags.contains(.maskControl) {
            result.insert(.control)
        }
        if flags.contains(.maskAlternate) {
            result.insert(.option)
        }
        if flags.contains(.maskSecondaryFn) {
            result.insert(.function)
        }
        return result
    }
}
