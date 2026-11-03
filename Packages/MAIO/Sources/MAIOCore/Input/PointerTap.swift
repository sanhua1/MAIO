import AppKit
import CoreGraphics
import MAIOKit
import Synchronization

/// 指针 tap：按阶段执行已注册的实时过滤器。没有过滤器时不运行，不产生任何开销。
final class PointerTap: Sendable {
    struct Entry: Sendable {
        let token: FilterToken
        let stage: FilterStage
        let filter: any RealtimeInputFilter
    }

    private struct State {
        var filters: [Entry] = []
        var frontmost: String?
    }

    private let state = Mutex(State())
    private let targets = TargetAppCache()
    private let remoteSources = RemoteSourceCache()
    private let runnerBox = Mutex<EventTapRunner?>(nil)

    var isRunning: Bool {
        runnerBox.withLock { $0?.isRunning ?? false }
    }

    var hasFilters: Bool {
        state.withLock { !$0.filters.isEmpty }
    }

    func start() -> Bool {
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        // 注释会话层：事件已确定目标进程，可按"鼠标所指的 App"套用规则（ADR-0006，与 Mos 相同）
        let runner = EventTapRunner(
            name: "pointer",
            mask: mask,
            location: .cgAnnotatedSessionEventTap,
            placement: .tailAppendEventTap,
        ) { [weak self] _, event in
            // 注意：不能写成 `self?.handle(...) ?? passUnretained(event)`。handle 返回 nil 表示"吞掉事件"，
            // 可选链会把这个 nil 当成 self 不存在，于是事件被放行（曾经的真实 bug，见 docs/PROGRESS.md）。
            guard let self else { return Unmanaged.passUnretained(event) }
            return self.handle(event)
        }
        guard runner.start() else { return false }
        runnerBox.withLock { $0 = runner }
        return true
    }

    func stop() {
        runnerBox.withLock {
            $0?.stop()
            $0 = nil
        }
    }

    func add(_ entry: Entry) {
        state.withLock { state in
            state.filters.append(entry)
            // 稳定排序：同阶段内按注册先后
            state.filters = state.filters.enumerated()
                .sorted { ($0.element.stage, $0.offset) < ($1.element.stage, $1.offset) }
                .map(\.element)
        }
    }

    func remove(_ token: FilterToken) {
        state.withLock { $0.filters.removeAll { $0.token == token } }
    }

    func update(frontmost: String?) {
        state.withLock { $0.frontmost = frontmost }
    }

    private func handle(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let (filters, frontmost) = state.withLock { ($0.filters, $0.frontmost) }
        guard !filters.isEmpty else { return Unmanaged.passUnretained(event) }
        // 远程控制软件注入的滚动：控制端已经处理过方向和平滑，原样放行（ADR-0013）
        let sourcePID = pid_t(truncatingIfNeeded: event.getIntegerValueField(.eventSourceUnixProcessID))
        guard !remoteSources.isRemote(sourcePID) else { return Unmanaged.passUnretained(event) }
        let original = ScrollEventCodec.decode(event)
        var current = original
        let targetPID = pid_t(truncatingIfNeeded: event.getIntegerValueField(.eventTargetUnixProcessID))
        let environment = RealtimeEnvironment(
            frontmostBundleID: frontmost,
            targetBundleID: targets.bundleID(for: targetPID),
            modifiers: EventPoster.modifiers(from: event.flags),
        )
        for entry in filters where entry.filter.process(&current, environment) == .consume {
            return nil
        }
        ScrollEventCodec.apply(current, original: original, to: event)
        return Unmanaged.passUnretained(event)
    }
}

/// 目标进程 → bundle ID 的缓存。滚动时目标很少变化，只在 pid 变化时查询一次。
private final class TargetAppCache: Sendable {
    private struct Entry {
        var pid: pid_t = 0
        var bundleID: String?
    }

    private let last = Mutex(Entry())

    func bundleID(for pid: pid_t) -> String? {
        guard pid > 1 else { return nil }
        if let cached = last.withLock({ $0.pid == pid ? $0.bundleID : nil }) {
            return cached
        }
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        last.withLock { $0 = Entry(pid: pid, bundleID: bundleID) }
        return bundleID
    }
}
