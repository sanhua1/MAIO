import Darwin
import Synchronization

/// 识别远程控制软件（屏幕共享、UU 远程、ToDesk 等）注入的事件（ADR-0013）。
/// 这些事件已经按控制端电脑的习惯处理过方向和平滑，被控端不应再反转或平滑。
/// 按发出事件的进程的可执行文件路径匹配关键字。
/// 参考：references/Mos/Mos/Utils/Constants.swift（REMOTE_CONTROL_APPLICATION 名单）
enum RemoteControlSource {
    /// 可执行文件路径关键字（不区分大小写）
    static let keywords = [
        "screensharingd", "ScreensharingAgent", "ARDAgent", // macOS 屏幕共享、Apple Remote Desktop
        "UURemote", // 网易 UU 远程
        "ToDesk",
        "Sunlogin", "AweSun", // 向日葵
        "TeamViewer", "AnyDesk", "Parsec", "RustDesk", "VNC",
    ]

    static func matches(executablePath path: String) -> Bool {
        keywords.contains { path.range(of: $0, options: .caseInsensitive) != nil }
    }

    /// 进程的可执行文件路径；进程已退出时为 nil
    static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(bytes: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, encoding: .utf8)
    }
}

/// 事件来源进程 → 是否远程控制软件。连续滚动时来源很少变化，只在 pid 变化时查询一次（tap 线程上调用）。
final class RemoteSourceCache: Sendable {
    private struct Entry {
        var pid: pid_t = 0
        var isRemote = false
    }

    private let last = Mutex(Entry())

    /// pid 为 0 是硬件事件
    func isRemote(_ pid: pid_t) -> Bool {
        guard pid > 0, pid != getpid() else { return false }
        if let cached = last.withLock({ $0.pid == pid ? $0.isRemote : nil }) {
            return cached
        }
        let isRemote = RemoteControlSource.executablePath(of: pid).map(RemoteControlSource.matches) ?? false
        last.withLock { $0 = Entry(pid: pid, isRemote: isRemote) }
        return isRemote
    }
}
