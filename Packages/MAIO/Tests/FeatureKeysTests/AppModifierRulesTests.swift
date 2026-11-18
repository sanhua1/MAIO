@testable import FeatureKeys
import Testing

struct AppModifierRulesTests {
    private let game = "com.riotgames.LeagueofLegends.GameClient"

    /// 用户的自带键盘从左到右 ⌘ ⌃ Fn ⌥：🌐→⌘、⌃→⌃、⌥→🌐、⌘→⌥
    private var userBuiltIn: ModifierMapping {
        var mapping = ModifierMapping(pairs: [])
        mapping.set(.globe, to: .command)
        mapping.set(.option, to: .globe)
        mapping.set(.command, to: .option)
        return mapping
    }

    @Test func `swap applies on top of the device mapping`() {
        let swaps: [ModifierKey: ModifierTarget] = [.command: .control, .control: .command]
        let composed = AppModifierRules.compose(userBuiltIn, swaps)
        // 最左边的键（物理 🌐）原来是 ⌘，游戏里变成 ⌃；第二个键（物理 ⌃）变成 ⌘
        #expect(composed.target(for: .globe) == .control)
        #expect(composed.target(for: .control) == .command)
        // 没有规则的键保持设备映射
        #expect(composed.target(for: .option) == .globe)
        #expect(composed.target(for: .command) == .option)
    }

    @Test func `swap on a keyboard without device mapping`() {
        let composed = AppModifierRules.compose(ModifierMapping(pairs: []), [.command: .noAction])
        #expect(composed.target(for: .command) == .noAction)
        #expect(composed.target(for: .control) == .control)
        // 空规则合成后还是空映射
        #expect(AppModifierRules.compose(ModifierMapping(pairs: []), [:]).isDefault)
    }

    @Test func `unknown pairs in the device mapping are kept`() {
        let other = MappingPair(source: 0x7_0000_0068, destination: 0x7_0000_0029)
        let composed = AppModifierRules.compose(ModifierMapping(pairs: [other]), [.command: .control])
        #expect(composed.pairs.contains(other))
    }

    @Test func `rule lookup by frontmost app`() {
        let rules = [
            AppModifierRule(bundleID: game, name: "LoL", swaps: [], isEnabled: true),
            AppModifierRule(bundleID: "a", name: "A", swaps: ModifierSwap.commandControl, isEnabled: false),
            AppModifierRule(bundleID: game, name: "LoL", swaps: ModifierSwap.commandControl + [
                ModifierSwap(from: .command, to: .option), ModifierSwap(from: .option, to: .option),
            ]),
        ]
        // 空规则、停用的规则跳过；同一个来源用第一条；A → A 不算
        #expect(AppModifierRules.swaps(for: game, in: rules) == [.command: .control, .control: .command])
        #expect(AppModifierRules.swaps(for: "a", in: rules) == nil)
        #expect(AppModifierRules.swaps(for: nil, in: rules) == nil)
    }
}
