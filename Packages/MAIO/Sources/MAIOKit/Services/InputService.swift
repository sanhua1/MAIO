/// 在 tap 线程上同步调用的指针过滤器（见 ARCHITECTURE §5.4）。
/// 约束：不得访问 @MainActor 状态，不得阻塞或做 IO；只能读自己持有的不可变配置快照。
public protocol RealtimeInputFilter: Sendable {
    func process(_ event: inout PointerEvent, _ environment: RealtimeEnvironment) -> FilterDecision
}

public enum FilterDecision: Sendable, Hashable {
    case pass
    /// 吞掉原始事件（例如平滑滚动接管后自行发出插值事件）
    case consume
}

/// 过滤器阶段。执行顺序由阶段决定，与注册先后无关。
public enum FilterStage: Int, Sendable, Comparable, CaseIterable {
    case observe = 0
    case transform = 1
    case smooth = 2

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct FilterToken: Sendable, Hashable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

/// 发送合成事件。线程安全，可以在 display link 等实时线程上调用。
public protocol SyntheticEventPoster: Sendable {
    func post(_ event: SyntheticEvent)
}

/// 键盘会话：会话期间，按键（down/up）全部交给会话并被吞掉；flagsChanged 也会送达，但不会被吞掉。
public protocol KeyboardSession: AnyObject, Sendable {
    var events: AsyncStream<KeyEvent> { get }
    func end()
}

/// 输入引擎对功能开放的能力。宿主在功能停用时会自动注销其过滤器、结束其会话。
@MainActor
public protocol InputService: AnyObject {
    func beginKeyboardSession() -> any KeyboardSession
    func registerFilter(_ filter: any RealtimeInputFilter, for kind: PointerEventKind, stage: FilterStage) -> FilterToken
    func removeFilter(_ token: FilterToken)
    var poster: any SyntheticEventPoster { get }
}
