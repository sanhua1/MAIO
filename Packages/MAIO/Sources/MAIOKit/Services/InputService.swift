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

/// 在键盘 tap 线程上同步调用的按键过滤器（ADR-0017）。收到 keyDown（包括按住产生的重复）和 flagsChanged；
/// flagsChanged 只能观察，返回值被忽略。
/// 位置在键盘会话、快捷键录制之后，快捷键匹配之前。约束同 `RealtimeInputFilter`。
public protocol RealtimeKeyFilter: Sendable {
    func process(_ event: KeyEvent, _ environment: RealtimeEnvironment) -> KeyFilterDecision
    /// 键盘会话（窗口切换、截图等）期间是否也生效（ADR-0025）。生效时 `replace` 的键交给会话而不是发给系统。
    var appliesDuringKeyboardSessions: Bool { get }
}

public extension RealtimeKeyFilter {
    var appliesDuringKeyboardSessions: Bool {
        false
    }
}

public enum KeyFilterDecision: Sendable, Hashable {
    case pass
    /// 吞掉这个键（对应的 keyUp 也会被吞掉）
    case consume
    /// 吞掉这个键，立即改发另一个组合键（合成事件不会再经过过滤器）
    case replace(KeyChord)
}

/// 在 tap 线程上同步调用的鼠标按钮过滤器（ADR-0023）。只收到按下；按下被吞掉或改发时，引擎自己吞掉对应的抬起。
/// 约束同 `RealtimeInputFilter`。
public protocol RealtimeButtonFilter: Sendable {
    func process(_ event: MouseButtonEvent, _ environment: RealtimeEnvironment) -> KeyFilterDecision
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
    /// 注册按键过滤器（ADR-0017）。按注册顺序执行，第一个不是 `pass` 的结果生效
    func registerKeyFilter(_ filter: any RealtimeKeyFilter) -> FilterToken
    /// 注册鼠标按钮过滤器（ADR-0023）。按注册顺序执行，第一个不是 `pass` 的结果生效
    func registerButtonFilter(_ filter: any RealtimeButtonFilter) -> FilterToken
    /// 注销指针过滤器、按键过滤器或鼠标按钮过滤器
    func removeFilter(_ token: FilterToken)
    var poster: any SyntheticEventPoster { get }
}
