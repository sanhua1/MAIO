import Foundation

/// 系统设置"将 F1、F2 等键用作标准功能键"（spec 3.1）。
/// 关闭时 F1 是亮度键，发出的不是普通按键事件，⌥F1 无法触发。
enum FunctionKeyState {
    static func usesStandardFunctionKeys() -> Bool {
        let value = CFPreferencesCopyAppValue("com.apple.keyboard.fnState" as CFString, ".GlobalPreferences" as CFString)
        return (value as? NSNumber)?.boolValue ?? false
    }
}
