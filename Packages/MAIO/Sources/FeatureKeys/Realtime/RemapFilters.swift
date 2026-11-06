import MAIOKit
import Synchronization

/// tap 线程上能读的 Caps 状态（`CapsKeyMonitor` 在它自己的线程上更新；Caps 分层关着时为 nil）
protocol CapsState: Sendable {
    var isHeld: Bool { get }
}

/// 键盘 tap 线程上的 Caps 层 + 全局改键（决策在 `CapsLayer`）。
/// 绑定的 MAIO 命令通过 `commands` 交给主线程执行。
final class KeyRemapFilter: RealtimeKeyFilter {
    struct Config: Sendable {
        var caps: (any CapsState)?
        var layer: [UInt16: LayerAction] = [:]
        var global: [UInt16: LayerAction] = [:]
    }

    private struct State {
        var config: Config
        var layer = CapsLayer()
    }

    private let state: Mutex<State>
    private let continuation: AsyncStream<CommandID>.Continuation

    init(config: Config, continuation: AsyncStream<CommandID>.Continuation) {
        state = Mutex(State(config: config))
        self.continuation = continuation
    }

    func update(_ config: Config) {
        state.withLock { $0.config = config }
    }

    func process(_ event: KeyEvent, _: RealtimeEnvironment) -> KeyFilterDecision {
        let result = state.withLock { value in
            let held = value.config.caps?.isHeld ?? false
            return value.layer.decide(event, capsHeld: held, map: value.config.layer, global: value.config.global)
        }
        if let command = result.command {
            continuation.yield(command)
        }
        return result.decision
    }
}

/// 鼠标中键、侧键（ADR-0023）。
final class MouseRemapFilter: RealtimeButtonFilter {
    private let map: Mutex<[Int: LayerAction]>
    private let continuation: AsyncStream<CommandID>.Continuation

    init(map: [Int: LayerAction], continuation: AsyncStream<CommandID>.Continuation) {
        self.map = Mutex(map)
        self.continuation = continuation
    }

    func update(_ map: [Int: LayerAction]) {
        self.map.withLock { $0 = map }
    }

    func process(_ event: MouseButtonEvent, _: RealtimeEnvironment) -> KeyFilterDecision {
        guard let action = map.withLock({ $0[event.button] }) else { return .pass }
        switch action {
        case let .keys(chord):
            return .replace(KeyChord(keyCode: chord.keyCode, modifiers: chord.modifiers.union(event.modifiers)))
        case let .command(id):
            continuation.yield(id)
            return .consume
        case let .hidKey(name):
            guard let code = HIDKey.named(name)?.keyCode else { return .pass }
            return .replace(KeyChord(keyCode: code, modifiers: event.modifiers))
        }
    }
}
