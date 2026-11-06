import CoreGraphics

/// 归一化后的键盘事件。
public struct KeyEvent: Sendable, Hashable {
    public enum Kind: Sendable, Hashable { case down, up, flagsChanged }

    public let kind: Kind
    public let keyCode: UInt16
    public let modifiers: KeyModifiers
    public let isRepeat: Bool

    public init(kind: Kind, keyCode: UInt16, modifiers: KeyModifiers, isRepeat: Bool = false) {
        self.kind = kind
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isRepeat = isRepeat
    }

    public var chord: KeyChord {
        KeyChord(keyCode: keyCode, modifiers: modifiers)
    }
}

/// 鼠标按钮按下（ADR-0023）。只有中键、侧键等（按钮号 ≥ 2），不含左右键。
public struct MouseButtonEvent: Sendable, Hashable {
    /// 2 中键、3 后退、4 前进，更多按钮依次往后
    public let button: Int
    public let modifiers: KeyModifiers

    public init(button: Int, modifiers: KeyModifiers) {
        self.button = button
        self.modifiers = modifiers
    }
}

/// 指针设备类型（见 ADR-0006）。
public enum PointerDeviceKind: Sendable, Hashable {
    /// 鼠标滚轮（包括 Logitech 平滑滚动驱动、远程桌面转发的连续滚轮事件，此时 `isContinuous` 为 true）
    case wheel
    /// 触控板、妙控鼠标：带手势阶段或惯性阶段
    case trackpad
}

/// 滚动阶段（触控板手势）。
public enum ScrollPhase: Sendable, Hashable {
    case none, mayBegin, began, changed, ended, cancelled
}

/// 惯性阶段。
public enum MomentumPhase: Sendable, Hashable {
    case none, began, changed, ended
}

public enum PointerEventKind: Sendable, Hashable {
    case scrollWheel
}

/// 交给实时过滤器的指针事件（对 CGEvent 的类型安全封装）。
/// 过滤器只修改 `scrollY` / `scrollX`（单位：行，可带小数），引擎会把修改按比例写回所有相关字段。
public struct PointerEvent: Sendable {
    public let kind: PointerEventKind
    public var scrollY: Double
    public var scrollX: Double
    /// 像素位移（只读；修改 scrollY/scrollX 时引擎会按比例同步像素字段）
    public let pixelY: Double
    public let pixelX: Double
    public let device: PointerDeviceKind
    /// 事件本身已是像素级连续滚动（触控板、平滑滚动驱动、远程桌面）
    public let isContinuous: Bool
    public let phase: ScrollPhase
    public let momentumPhase: MomentumPhase
    public let location: CGPoint
    /// MAIO 自己发出的合成事件
    public let isSynthetic: Bool

    public init(
        kind: PointerEventKind = .scrollWheel,
        scrollY: Double,
        scrollX: Double,
        pixelY: Double? = nil,
        pixelX: Double? = nil,
        device: PointerDeviceKind,
        isContinuous: Bool = false,
        phase: ScrollPhase = .none,
        momentumPhase: MomentumPhase = .none,
        location: CGPoint = .zero,
        isSynthetic: Bool = false,
    ) {
        self.kind = kind
        self.scrollY = scrollY
        self.scrollX = scrollX
        self.pixelY = pixelY ?? scrollY * 10
        self.pixelX = pixelX ?? scrollX * 10
        self.device = device
        self.isContinuous = isContinuous
        self.phase = phase
        self.momentumPhase = momentumPhase
        self.location = location
        self.isSynthetic = isSynthetic
    }
}

/// 实时过滤器可以读取的环境（由引擎原子维护，无需访问主线程）。
public struct RealtimeEnvironment: Sendable {
    public let frontmostBundleID: String?
    /// 事件目标进程（滚动时即鼠标所指窗口所属的 App）
    public let targetBundleID: String?
    public let modifiers: KeyModifiers

    public init(frontmostBundleID: String?, targetBundleID: String? = nil, modifiers: KeyModifiers) {
        self.frontmostBundleID = frontmostBundleID
        self.targetBundleID = targetBundleID
        self.modifiers = modifiers
    }

    /// 应用"按 App 例外"规则时使用：优先目标 App，其次前台 App。
    public var effectiveBundleID: String? {
        targetBundleID ?? frontmostBundleID
    }
}

/// MAIO 发出的合成事件。只能通过 `SyntheticEventPoster` 发送，引擎会统一打标记。
public enum SyntheticEvent: Sendable, Hashable {
    /// 完整按下并抬起一个组合键（键位重映射）
    case keyStroke(KeyChord)
    /// 像素级滚动（平滑滚动使用）
    case scroll(deltaY: Double, deltaX: Double, phase: ScrollPhase, momentumPhase: MomentumPhase)
    /// 触控板双指捏合缩放（ADR-0015）。一次缩放 = began → 若干 changed → ended；
    /// magnification 是这一步的增量，正数放大（0.01 ≈ 放大 1%），began / ended 时为 0
    case magnify(phase: ScrollPhase, magnification: Double)
}
