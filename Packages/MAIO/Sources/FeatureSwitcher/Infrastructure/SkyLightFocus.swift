import ApplicationServices
import CoreGraphics
import Foundation

/// 把"某个具体窗口"设为前台并获得键盘焦点（效果等同于在 Dock / 窗口上点击）。
///
/// 背景（ADR-0008 备选方案 1，2026-11-02 启用）：公开 API（AX 提升 + `NSRunningApplication.activate`）
/// 偶尔会让目标窗口停在上一个 App 的窗口下面——用户实测切到 QQ 时被 Otty 盖住。
///
/// 做法源自 yabai / Hammerspoon（https://github.com/Hammerspoon/hammerspoon/issues/370），
/// alt-tab-macos 对数据格式做了修正（references/alt-tab-macos/src/macos/api-wrappers/SkyLight.framework.swift）。
/// 这里按相同规格独立实现。所有私有函数在运行时用 dlsym 查找，缺失时 `isAvailable` 为 false，调用方退回公开 API。
enum SkyLightFocus {
    private typealias GetProcessForPID = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private typealias SetFrontProcess = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    private typealias PostEventRecord = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>)
        -> CGError

    private struct Functions: @unchecked Sendable {
        let getProcess: GetProcessForPID
        let setFront: SetFrontProcess
        let postEvent: PostEventRecord
    }

    private static let functions: Functions? = {
        let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        // GetProcessForPID 已弃用但仍可用；用 dlsym 调用，避免弃用警告（项目把警告视为错误）
        guard let getProcess = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "GetProcessForPID"),
              let setFront = dlsym(skyLight, "_SLPSSetFrontProcessWithOptions"),
              let postEvent = dlsym(skyLight, "SLPSPostEventRecordTo") else { return nil }
        return Functions(
            getProcess: unsafeBitCast(getProcess, to: GetProcessForPID.self),
            setFront: unsafeBitCast(setFront, to: SetFrontProcess.self),
            postEvent: unsafeBitCast(postEvent, to: PostEventRecord.self),
        )
    }()

    static var isAvailable: Bool {
        functions != nil
    }

    /// 返回 false 表示私有函数不可用或调用失败，调用方应退回公开 API。
    @discardableResult
    static func focus(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard let functions else { return false }
        var psn = ProcessSerialNumber()
        guard functions.getProcess(pid, &psn) == noErr else { return false }
        // 0x200 = 用户发起的切换（只把这个窗口带到前面，不是 App 的全部窗口）
        guard functions.setFront(&psn, windowID, Mode.userGenerated) == .success else { return false }
        postMakeKey(&psn, windowID: windowID, using: functions)
        return true
    }

    private enum Mode {
        static let userGenerated: UInt32 = 0x200
    }

    /// 事件记录格式（逆向得到，见上方出处）：
    /// - 缓冲区 0x100 字节且全部清零：macOS 14.7.4 起 WindowServer 会读到记录之外，不清零会崩溃
    /// - 0x04 记录长度 0xF8；0x08 事件类型 = 鼠标左键按下（只发按下、不发抬起：窗口获得焦点，但不会点到任何控件）
    /// - 0x20 窗口内坐标：放在任何窗口都够不到的右下远处，避免点到内容或缩放边缘
    /// - 0x3A 固定为 0x10；0x3C 目标窗口 ID（事件按 ID 投递，不按坐标）
    private static func postMakeKey(_ psn: inout ProcessSerialNumber, windowID: CGWindowID, using functions: Functions) {
        var bytes = [UInt8](repeating: 0, count: 0x100)
        bytes[0x04] = 0xF8
        bytes[0x08] = 0x01
        bytes[0x3A] = 0x10
        var point = CGPoint(x: 300_000, y: 300_000)
        var id = windowID
        bytes.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            memcpy(base + 0x20, &point, MemoryLayout<CGPoint>.size)
            memcpy(base + 0x3C, &id, MemoryLayout<CGWindowID>.size)
        }
        _ = functions.postEvent(&psn, &bytes)
    }
}

/// 屏幕上最上层的普通窗口（用于切换后检查是否成功）。
enum ScreenOrder {
    static func topWindowID() -> CGWindowID? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        let first = list.first { ($0[kCGWindowLayer as String] as? Int) == 0 }
        return first?[kCGWindowNumber as String] as? CGWindowID
    }

    static func ownerName(of windowID: CGWindowID) -> String {
        guard let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]],
              let name = list.first?[kCGWindowOwnerName as String] as? String else { return "?" }
        return name
    }
}
