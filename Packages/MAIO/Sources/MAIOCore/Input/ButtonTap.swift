import CoreGraphics
import MAIOKit
import Synchronization

/// 鼠标按钮 tap（ADR-0023）：中键、侧键交给已注册的按钮过滤器。没有过滤器时不运行。
final class ButtonTap: Sendable {
    private struct Entry {
        let token: FilterToken
        let filter: any RealtimeButtonFilter
    }

    private struct State {
        var filters: [Entry] = []
        var frontmost: String?
        /// 按下被吞掉或改发的按钮：对应的抬起也要吞掉
        var swallowed: Set<Int> = []
    }

    private let state = Mutex(State())
    private let runnerBox = Mutex<EventTapRunner?>(nil)
    private let poster: EventPoster

    init(poster: EventPoster) {
        self.poster = poster
    }

    func add(token: FilterToken, filter: any RealtimeButtonFilter) {
        state.withLock { $0.filters.append(Entry(token: token, filter: filter)) }
    }

    func remove(_ token: FilterToken) {
        state.withLock { $0.filters.removeAll { $0.token == token } }
    }

    func update(frontmost: String?) {
        state.withLock { $0.frontmost = frontmost }
    }

    /// 有过滤器时运行，没有时停掉
    func refresh() {
        let needed = state.withLock { !$0.filters.isEmpty }
        let running = runnerBox.withLock { $0?.isRunning ?? false }
        if needed, !running {
            start()
        } else if !needed, running {
            stop()
        }
    }

    func stop() {
        runnerBox.withLock {
            $0?.stop()
            $0 = nil
        }
        state.withLock { $0.swallowed.removeAll() }
    }

    private func start() {
        let mask = CGEventMask(1 << CGEventType.otherMouseDown.rawValue) | CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
        let runner = EventTapRunner(name: "buttons", mask: mask, location: .cgSessionEventTap) { [weak self] type, event in
            // 不能写成 `self?.handle(...) ?? passUnretained(event)`，见 PointerTap
            guard let self else { return Unmanaged.passUnretained(event) }
            return self.handle(type, event)
        }
        guard runner.start() else { return }
        runnerBox.withLock { $0 = runner }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        guard !SyntheticMarker.isMarked(event) else { return pass }
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        guard button >= 2 else { return pass }
        if type == .otherMouseUp {
            return state.withLock { $0.swallowed.remove(button) } == nil ? pass : nil
        }
        guard type == .otherMouseDown else { return pass }
        let modifiers = EventPoster.modifiers(from: event.flags)
        let (filters, frontmost) = state.withLock { ($0.filters, $0.frontmost) }
        let environment = RealtimeEnvironment(frontmostBundleID: frontmost, modifiers: modifiers)
        for entry in filters {
            let decision = entry.filter.process(MouseButtonEvent(button: button, modifiers: modifiers), environment)
            switch decision {
            case .pass: continue
            case .consume:
                state.withLock { _ = $0.swallowed.insert(button) }
                return nil
            case let .replace(chord):
                state.withLock { _ = $0.swallowed.insert(button) }
                poster.post(.keyStroke(chord))
                return nil
            }
        }
        return pass
    }
}
