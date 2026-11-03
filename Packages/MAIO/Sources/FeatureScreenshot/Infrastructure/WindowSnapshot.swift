import AppKit

/// 读取当前屏幕上的窗口列表（约 1 ms，ADR-0011）。
enum WindowSnapshot {
    @MainActor static func current() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        var bundles: [Int32: String?] = [:]
        return list.compactMap { entry in
            guard let id = entry[kCGWindowNumber as String] as? UInt32,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                  let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDictionary) else { return nil }
            if bundles[pid] == nil {
                bundles[pid] = .some(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier)
            }
            return WindowInfo(
                id: id,
                pid: pid,
                frame: frame,
                layer: entry[kCGWindowLayer as String] as? Int ?? 0,
                alpha: entry[kCGWindowAlpha as String] as? Double ?? 1,
                ownerName: entry[kCGWindowOwnerName as String] as? String ?? "",
                bundleID: bundles[pid].flatMap(\.self),
            )
        }
    }
}
