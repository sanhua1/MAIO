@testable import FeatureKeys
import MAIOKit
import Testing

struct GlobalRemapsTests {
    private func chord(_ string: String) -> KeyChord {
        KeyChord(string: string) ?? KeyChord(keyCode: 0, modifiers: [])
    }

    @Test func `key table matches HID usages and key codes`() {
        #expect(HIDKey.named("a")?.usage == 0x7_0000_0004)
        #expect(HIDKey.named("a")?.keyCode == 0)
        #expect(HIDKey.named("0")?.usage == 0x7_0000_0027)
        #expect(HIDKey.named("f1")?.usage == 0x7_0000_003A)
        #expect(HIDKey.named("f13")?.usage == 0x7_0000_0068)
        #expect(HIDKey.named("f13")?.keyCode == 105)
        #expect(HIDKey.named("f23")?.usage == 0x7_0000_0072)
        #expect(HIDKey.named("f23")?.keyCode == nil)
        #expect(HIDKey.named("fn")?.usage == HIDUsage.topCaseFn)
        #expect(HIDKey.with(keyCode: 115)?.name == "home")
        #expect(Set(HIDKey.all.map(\.name)).count == HIDKey.all.count)
    }

    /// 用户原来 Karabiner 的全局改键：F23 → Fn（HID 层），Home / End → ⌘← / ⌘→（tap 层）
    @Test func `remaps split between HID and tap layers`() {
        let remaps = [
            KeyRemap(from: "f23", action: .hidKey("fn")),
            KeyRemap(from: "home", action: .keys(chord("cmd+left"))),
            KeyRemap(from: "end", action: .keys(chord("cmd+right"))),
            KeyRemap(from: "f24", action: .keys(chord("cmd+c"))),
            KeyRemap(from: "f22", action: .hidKey("escape"), isEnabled: false),
        ]
        #expect(GlobalRemaps.hidPairs(remaps) == [MappingPair(source: 0x7_0000_0072, destination: HIDUsage.topCaseFn)])
        // F24 没有虚拟键码，做不了组合键；停用的不算
        #expect(GlobalRemaps.tapMap(remaps) == [115: .keys(chord("cmd+left")), 119: .keys(chord("cmd+right"))])
    }

    @Test func `global remap applies outside the layer with modifiers stacked`() {
        var layer = CapsLayer()
        let global: [UInt16: LayerAction] = [115: .keys(chord("cmd+left"))]
        let home = KeyEvent(kind: .down, keyCode: 115, modifiers: .shift)
        #expect(layer.decide(home, capsHeld: false, map: [:], global: global).decision == .replace(chord("shift+cmd+left")))
        // 按住 Caps 时用层的设置，层里没有就照常
        #expect(layer.decide(home, capsHeld: true, map: [:], global: global).decision == .pass)
    }

    @Test func `mouse buttons map first enabled entry`() {
        let remaps = [
            MouseRemap(button: 3, action: .keys(chord("cmd+w"))),
            MouseRemap(button: 3, action: .keys(chord("cmd+q"))),
            MouseRemap(button: 4, action: .keys(chord("cmd+q")), isEnabled: false),
        ]
        #expect(GlobalRemaps.buttonMap(remaps) == [3: .keys(chord("cmd+w"))])
    }

    @Test func `mouse filter replaces and runs commands`() {
        let (_, continuation) = AsyncStream<CommandID>.makeStream()
        let filter = MouseRemapFilter(map: [3: .keys(chord("cmd+w")), 4: .command("launcher.show")], continuation: continuation)
        let environment = RealtimeEnvironment(frontmostBundleID: nil, modifiers: [])
        #expect(filter.process(MouseButtonEvent(button: 3, modifiers: .shift), environment) == .replace(chord("shift+cmd+w")))
        #expect(filter.process(MouseButtonEvent(button: 4, modifiers: []), environment) == .consume)
        #expect(filter.process(MouseButtonEvent(button: 2, modifiers: []), environment) == .pass)
    }
}
