/// 媒体键（ADR-0028）：键盘、鼠标（例如绑成"音量加"的侧键）发出的音量、亮度键。
public enum MediaKey: Sendable, Hashable, CaseIterable {
    case volumeUp, volumeDown, mute
    case brightnessUp, brightnessDown

    public var isVolume: Bool {
        switch self {
        case .volumeUp, .volumeDown, .mute: true
        case .brightnessUp, .brightnessDown: false
        }
    }
}

/// 媒体键按下（包括按住产生的重复）。抬起不交给过滤器：按下被吞掉时，引擎自己吞掉对应的抬起。
public struct MediaKeyEvent: Sendable, Hashable {
    public let key: MediaKey
    public let isRepeat: Bool
    public let modifiers: KeyModifiers

    public init(key: MediaKey, isRepeat: Bool = false, modifiers: KeyModifiers = []) {
        self.key = key
        self.isRepeat = isRepeat
        self.modifiers = modifiers
    }
}

/// 在键盘 tap 线程上同步调用的媒体键过滤器（ADR-0028）。约束同 `RealtimeInputFilter`：
/// 不访问 @MainActor 状态，不阻塞、不做 IO，只读自己持有的快照；要做的事异步交出去。
/// 返回 `consume` 时系统收不到这个键（不会再弹"无法调节"的提示）。
public protocol RealtimeMediaKeyFilter: Sendable {
    func process(_ event: MediaKeyEvent) -> FilterDecision
}
