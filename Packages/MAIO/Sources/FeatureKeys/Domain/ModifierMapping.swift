/// HID 用法值：`(usagePage << 32) | usage`，和系统修饰键设置里存的整数一样。
enum HIDUsage {
    static func keyboard(_ usage: UInt64) -> UInt64 {
        0x7_0000_0000 | usage
    }

    /// 🌐 / Fn 作为来源时，新款键盘发的是 0xFF01 页，老款是 0x00FF 页（Apple 顶盖页）
    static let globeKey: UInt64 = 0xFF01_0000_0003
    static let topCaseFn: UInt64 = 0xFF_0000_0003
    static let noAction = keyboard(0)
}

/// 系统设置"修饰键"里能改的键
enum ModifierKey: String, CaseIterable, Sendable {
    case capsLock, control, option, command, globe

    /// 这个键发出的用法值（左、右）
    var sources: [UInt64] {
        switch self {
        case .capsLock: [HIDUsage.keyboard(0x39)]
        case .control: [HIDUsage.keyboard(0xE0), HIDUsage.keyboard(0xE4)]
        case .option: [HIDUsage.keyboard(0xE2), HIDUsage.keyboard(0xE6)]
        case .command: [HIDUsage.keyboard(0xE3), HIDUsage.keyboard(0xE7)]
        case .globe: [HIDUsage.globeKey, HIDUsage.topCaseFn]
        }
    }

    var title: String {
        switch self {
        case .capsLock: "⇪ 大写锁定"
        case .control: "⌃ Control"
        case .option: "⌥ Option"
        case .command: "⌘ Command"
        case .globe: "🌐 地球仪 / Fn"
        }
    }
}

/// 修饰键改成什么
enum ModifierTarget: String, CaseIterable, Sendable {
    case capsLock, control, option, command, globe, escape, noAction

    init(_ key: ModifierKey) {
        switch key {
        case .capsLock: self = .capsLock
        case .control: self = .control
        case .option: self = .option
        case .command: self = .command
        case .globe: self = .globe
        }
    }

    /// 映射到的用法值（左、右）；和系统设置写的一致
    var destinations: [UInt64] {
        switch self {
        case .capsLock: [HIDUsage.keyboard(0x39), HIDUsage.keyboard(0x39)]
        case .control: [HIDUsage.keyboard(0xE0), HIDUsage.keyboard(0xE4)]
        case .option: [HIDUsage.keyboard(0xE2), HIDUsage.keyboard(0xE6)]
        case .command: [HIDUsage.keyboard(0xE3), HIDUsage.keyboard(0xE7)]
        case .globe: [HIDUsage.topCaseFn, HIDUsage.topCaseFn]
        case .escape: [HIDUsage.keyboard(0x29), HIDUsage.keyboard(0x29)]
        case .noAction: [HIDUsage.noAction, HIDUsage.noAction]
        }
    }

    var title: String {
        switch self {
        case .capsLock: "⇪ 大写锁定"
        case .control: "⌃ Control"
        case .option: "⌥ Option"
        case .command: "⌘ Command"
        case .globe: "🌐 地球仪 / Fn"
        case .escape: "⎋ Esc"
        case .noAction: "无操作"
        }
    }

    static func matching(_ destination: UInt64) -> ModifierTarget? {
        allCases.first { $0.destinations.contains(destination) }
    }
}

/// 一条映射：来源用法值 → 目标用法值
struct MappingPair: Hashable, Sendable {
    let source: UInt64
    let destination: UInt64
}

/// 一个键盘的修饰键设置。从系统存的映射读出来，改完再生成系统格式的映射。
/// 不认识的映射（别的工具写的、MAIO 不管的键）原样保留。
struct ModifierMapping: Equatable, Sendable {
    /// 只记改过的键
    private(set) var targets: [ModifierKey: ModifierTarget] = [:]
    private var others: [MappingPair] = []

    init(pairs: [MappingPair]) {
        var others: [MappingPair] = []
        for pair in pairs {
            guard let key = ModifierKey.allCases.first(where: { $0.sources.contains(pair.source) }),
                  let target = ModifierTarget.matching(pair.destination)
            else {
                others.append(pair)
                continue
            }
            // 左键的映射决定显示；右键的映射跟着它重新生成
            if pair.source == key.sources[0] || targets[key] == nil {
                targets[key] = target
            }
        }
        self.others = others
        targets = targets.filter { $0.value != ModifierTarget($0.key) }
    }

    var isDefault: Bool {
        targets.isEmpty && others.isEmpty
    }

    func target(for key: ModifierKey) -> ModifierTarget {
        targets[key] ?? ModifierTarget(key)
    }

    mutating func set(_ key: ModifierKey, to target: ModifierTarget) {
        others.removeAll { key.sources.contains($0.source) }
        targets[key] = target == ModifierTarget(key) ? nil : target
    }

    /// 系统格式的映射：改过的键左右各一条，加上原样保留的
    var pairs: [MappingPair] {
        let mine = ModifierKey.allCases.flatMap { key -> [MappingPair] in
            guard let target = targets[key] else { return [] }
            return zip(key.sources, target.destinations).map { MappingPair(source: $0, destination: $1) }
        }
        return mine + others
    }
}
