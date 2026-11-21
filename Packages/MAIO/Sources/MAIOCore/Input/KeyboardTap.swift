import AppKit
import CoreGraphics
import MAIOKit
import Synchronization

/// 键盘 tap：快捷键匹配、键盘会话、快捷键录制。
final class KeyboardTap: Sendable {
    private struct State {
        var router = KeyboardRouter()
        var normalizer = KeyNormalizer()
        var sessions: [EngineKeyboardSession] = []
        var recorder: (@Sendable (KeyChord) -> Void)?
        var media = MediaKeyRouter()
    }

    private let state = Mutex(State())
    private let onFire: @Sendable (CommandBinding) -> Void
    private let poster: any SyntheticEventPoster
    private let runnerBox = Mutex<EventTapRunner?>(nil)

    init(poster: any SyntheticEventPoster, onFire: @escaping @Sendable (CommandBinding) -> Void) {
        self.poster = poster
        self.onFire = onFire
    }

    var isRunning: Bool {
        runnerBox.withLock { $0?.isRunning ?? false }
    }

    func start() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue) | (1 << MediaKeyRouter.systemDefinedType)
        let runner = EventTapRunner(name: "keyboard", mask: CGEventMask(mask)) { [weak self] type, event in
            // 注意：不能写成 `self?.handle(...) ?? passUnretained(event)`。handle 返回 nil 表示"吞掉事件"，
            // 可选链会把这个 nil 当成 self 不存在，于是事件被放行（曾经的真实 bug，见 docs/PROGRESS.md）。
            guard let self else { return Unmanaged.passUnretained(event) }
            return self.handle(type: type, event: event)
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

    // MARK: 主线程更新状态

    func update(table: HotkeyTable) {
        state.withLock { $0.router.table = table }
    }

    func update(frontmost: String?) {
        state.withLock { $0.router.frontmost = frontmost }
    }

    func update(passthroughApps: Set<String>) {
        state.withLock { $0.router.passthroughApps = passthroughApps }
    }

    func setRecorder(_ recorder: (@Sendable (KeyChord) -> Void)?) {
        state.withLock {
            $0.recorder = recorder
            $0.router.isRecording = recorder != nil
        }
    }

    func add(_ entry: KeyFilterEntry) {
        state.withLock { $0.router.filters.append(entry) }
    }

    func addMediaKeyFilter(token: FilterToken, filter: any RealtimeMediaKeyFilter) {
        state.withLock { $0.media.filters.append(.init(token: token, filter: filter)) }
    }

    func removeFilter(_ token: FilterToken) {
        state.withLock {
            $0.router.filters.removeAll { $0.token == token }
            $0.media.filters.removeAll { $0.token == token }
        }
    }

    func beginSession() -> EngineKeyboardSession {
        let session = EngineKeyboardSession { [weak self] ended in
            self?.state.withLock { state in
                state.sessions.removeAll { $0 === ended }
                state.router.hasSession = !state.sessions.isEmpty
            }
        }
        state.withLock {
            $0.sessions.append(session)
            $0.router.hasSession = true
        }
        return session
    }

    // MARK: tap 线程

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if !SyntheticMarker.isMarked(event), handleMediaKey(type: type, event: event) {
            return nil
        }
        guard !SyntheticMarker.isMarked(event), let kind = Self.kind(of: type) else {
            return Unmanaged.passUnretained(event)
        }
        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let (decision, session, recorder) = state.withLock { state in
            let keyEvent = state.normalizer.normalize(
                kind: kind, keyCode: keyCode, flags: event.flags.rawValue, isRepeat: isRepeat,
            )
            return (state.router.route(keyEvent), state.sessions.last, state.recorder)
        }
        switch decision.effect {
        case let .toSession(keyEvent): session?.yield(keyEvent)
        case let .toRecorder(chord): recorder?(chord)
        case let .fire(binding): onFire(binding)
        // 在 tap 线程上立即发出，保证排在后面的真实按键之前
        case let .post(chord): poster.post(.keyStroke(chord))
        case nil: break
        }
        return decision.consume ? nil : Unmanaged.passUnretained(event)
    }

    /// 媒体键（ADR-0028）：返回 true 表示被过滤器吞掉。没有媒体键过滤器时什么也不做。
    private func handleMediaKey(type: CGEventType, event: CGEvent) -> Bool {
        guard state.withLock({ !$0.media.filters.isEmpty }) else { return false }
        let decoded: (key: MediaKey, isDown: Bool, isRepeat: Bool)
        let source: MediaKeyRouter.Source
        if type.rawValue == MediaKeyRouter.systemDefinedType {
            // 系统定义事件的 data1 只能经 NSEvent 读取（在 tap 线程上创建 NSEvent 是安全的）
            guard let nsEvent = NSEvent(cgEvent: event),
                  let media = MediaKeyRouter.decode(subtype: nsEvent.subtype.rawValue, data1: nsEvent.data1)
            else { return false }
            decoded = media
            source = .systemDefined
        } else if type == .keyDown || type == .keyUp,
                  let key = MediaKeyRouter.brightnessKey(
                      keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
                  ) {
            decoded = (key, type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
            source = .keyCode
        } else {
            return false
        }
        let modifiers = KeyNormalizer.modifiers(flags: event.flags.rawValue)
        return state.withLock {
            $0.media.route(
                key: decoded.key, isDown: decoded.isDown, isRepeat: decoded.isRepeat, modifiers: modifiers,
                source: source, time: event.timestamp,
            )
        }
    }

    private static func kind(of type: CGEventType) -> KeyEvent.Kind? {
        switch type {
        case .keyDown: .down
        case .keyUp: .up
        case .flagsChanged: .flagsChanged
        default: nil
        }
    }
}

/// 键盘会话的引擎实现。
final class EngineKeyboardSession: KeyboardSession {
    let events: AsyncStream<KeyEvent>
    private let continuation: AsyncStream<KeyEvent>.Continuation
    private let onEnd: @Sendable (EngineKeyboardSession) -> Void
    private let ended = Mutex(false)

    init(onEnd: @escaping @Sendable (EngineKeyboardSession) -> Void) {
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(64))
        self.onEnd = onEnd
    }

    func yield(_ event: KeyEvent) {
        continuation.yield(event)
    }

    func end() {
        let wasEnded = ended.withLock { value in
            defer { value = true }
            return value
        }
        guard !wasEnded else { return }
        continuation.finish()
        onEnd(self)
    }
}
