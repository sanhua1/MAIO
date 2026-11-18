/// 按 App 改修饰键的一条规则（ADR-0026）：这个 App 在前台时，修饰键 A 当作 B。
struct AppModifierRule: Codable, Sendable, Hashable {
    var bundleID: String
    /// 显示用的名字（选 App 时记下）
    var name: String
    var swaps: [ModifierSwap]
    var isEnabled = true
}

/// 一条"修饰键 → 修饰键"。来源是设备映射之后的修饰键（用户感觉上的那个键）。
struct ModifierSwap: Codable, Sendable, Hashable {
    var from: ModifierKey
    var to: ModifierTarget

    /// 规则能改的键：Caps 归 Super Caps 管
    static let sources: [ModifierKey] = [.command, .control, .option, .globe]
    static let targets: [ModifierTarget] = [.command, .control, .option, .globe, .escape, .noAction]

    /// ⌘ ↔ ⌃ 对调（新规则的默认值）
    static let commandControl = [
        ModifierSwap(from: .command, to: .control),
        ModifierSwap(from: .control, to: .command),
    ]
}

extension ModifierKey: Codable {}
extension ModifierTarget: Codable {}

enum AppModifierRules {
    /// 前台 App 对应的规则：第一条启用、bundle ID 相同、至少有一条有效改动的规则。
    /// 返回 来源键 → 目标（同一个来源多条时用第一条；A → A 不算）
    static func swaps(for bundleID: String?, in rules: [AppModifierRule]) -> [ModifierKey: ModifierTarget]? {
        guard let bundleID else { return nil }
        for rule in rules where rule.isEnabled && rule.bundleID == bundleID {
            let map = rule.swaps.reduce(into: [ModifierKey: ModifierTarget]()) { map, swap in
                if map[swap.from] == nil, ModifierSwap.sources.contains(swap.from) {
                    map[swap.from] = swap.to
                }
            }.filter { $0.value != ModifierTarget($0.key) }
            if !map.isEmpty {
                return map
            }
        }
        return nil
    }

    /// 合成：每个物理键先按设备映射得到修饰键 m，m 有规则时改成规则的目标。设备映射里不认识的条目原样保留
    static func compose(_ base: ModifierMapping, _ swaps: [ModifierKey: ModifierTarget]) -> ModifierMapping {
        var result = base
        for key in ModifierKey.allCases {
            guard let logical = ModifierKey(target: base.target(for: key)), let target = swaps[logical] else { continue }
            result.set(key, to: target)
        }
        return result
    }
}

extension ModifierKey {
    /// 映射目标对应的修饰键（Esc、无操作没有）
    init?(target: ModifierTarget) {
        switch target {
        case .capsLock: self = .capsLock
        case .control: self = .control
        case .option: self = .option
        case .command: self = .command
        case .globe: self = .globe
        case .escape, .noAction: return nil
        }
    }
}
