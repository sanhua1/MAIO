import CoreGraphics
import MAIOKit
import Synchronization

/// 媒体键过滤器（tap 线程）：该由 MAIO 调的键吞掉并交出去，其余放行给系统。
/// - 音量键：当前声音输出系统调不了、而且对应一台能用 DDC 调音量的显示器
/// - 亮度键：鼠标所在的屏幕是一台能用 DDC 调亮度的外接显示器（在内建屏上时交给系统）
final class DisplayMediaKeyFilter: RealtimeMediaKeyFilter {
    struct Snapshot: Sendable, Equatable {
        var volumeDisplay: CGDirectDisplayID?
        var brightnessDisplays: Set<CGDirectDisplayID> = []
    }

    private let snapshot = Mutex(Snapshot())
    /// 在 tap 线程上调用，实现只能把事件转交出去，不能阻塞
    private let onKey: @Sendable (MediaKeyEvent, CGDirectDisplayID) -> Void

    init(onKey: @escaping @Sendable (MediaKeyEvent, CGDirectDisplayID) -> Void) {
        self.onKey = onKey
    }

    func update(_ value: Snapshot) {
        snapshot.withLock { $0 = value }
    }

    func process(_ event: MediaKeyEvent) -> FilterDecision {
        let current = snapshot.withLock { $0 }
        let target: CGDirectDisplayID? = if event.key.isVolume {
            current.volumeDisplay
        } else {
            Self.brightnessTarget(current.brightnessDisplays)
        }
        guard let target else { return .pass }
        onKey(event, target)
        return .consume
    }

    /// 鼠标所在的屏幕；找不到（例如显示器在睡眠）而只有一台可调的外接显示器时就是它
    private static func brightnessTarget(_ candidates: Set<CGDirectDisplayID>) -> CGDirectDisplayID? {
        if let display = displayUnderCursor() {
            return candidates.contains(display) ? display : nil
        }
        return candidates.count == 1 ? candidates.first : nil
    }

    private static func displayUnderCursor() -> CGDirectDisplayID? {
        guard let location = CGEvent(source: nil)?.location else { return nil }
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(location, 1, &display, &count) == .success, count > 0 else { return nil }
        return display
    }
}
