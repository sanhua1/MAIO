import AppKit

/// 把 MAIO 强制激活到前台。
/// macOS 14 起 `NSApp.activate()` 只是"请求"，从菜单栏菜单或全局快捷键调用时常被系统拒绝（窗口在最前却没有焦点）。
/// 这里通过协议调用 `activate(ignoringOtherApps:)`（已标记弃用但仍然有效），避免弃用警告。见 docs/PROGRESS.md。
@MainActor
public enum AppActivation {
    public static func activateForcibly() {
        (NSApp as any ForcedActivation).activate(ignoringOtherApps: true)
    }
}

@MainActor
private protocol ForcedActivation {
    func activate(ignoringOtherApps flag: Bool)
}

extension NSApplication: ForcedActivation {}
