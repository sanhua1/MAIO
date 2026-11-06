import Darwin

/// Karabiner-Elements 在运行时会独占键盘、从自己的虚拟键盘发出按键，系统的修饰键设置对实体键盘不起作用。
enum KarabinerDetector {
    /// 独占键盘的后台进程（root 运行，NSWorkspace 看不到，按进程名找）
    static let processNames: Set<String> = ["Karabiner-Core-Service", "karabiner_grabber"]

    static func isRunning() -> Bool {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return false }
        var pids = [pid_t](repeating: 0, count: Int(count) * 2)
        let filled = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard filled > 0 else { return false }
        return pids.prefix(Int(filled)).contains { pid in
            var name = [CChar](repeating: 0, count: Int(MAXCOMLEN) * 2 + 1)
            guard proc_name(pid, &name, UInt32(name.count)) > 0 else { return false }
            let bytes = name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            return String(bytes: bytes, encoding: .utf8).map(processNames.contains) ?? false
        }
    }
}
