@testable import FeatureKeys
import MAIOKit
import Testing

struct CapsLayerTests {
    static let map = KeysSettings.defaultValue.layerMap
    static let w: UInt16 = 13, g: UInt16 = 5, t: UInt16 = 17

    private func down(_ code: UInt16, _ modifiers: KeyModifiers = [], repeat isRepeat: Bool = false) -> KeyEvent {
        KeyEvent(kind: .down, keyCode: code, modifiers: modifiers, isRepeat: isRepeat)
    }

    private func chord(_ string: String) -> KeyChord {
        KeyChord(string: string) ?? KeyChord(keyCode: 0, modifiers: [])
    }

    @Test func `default layer is the Karabiner setup`() {
        #expect(Self.map.count == 8)
        #expect(Self.map[Self.w] == .keys(chord("up")))
        #expect(Self.map[7] == .keys(chord("cmd+left")))
    }

    @Test func `mapped key in layer is replaced and modifiers stack`() {
        var layer = CapsLayer()
        #expect(layer.decide(down(Self.w), capsHeld: true, map: Self.map).decision == .replace(chord("up")))
        #expect(layer.decide(down(1, .shift), capsHeld: true, map: Self.map).decision == .replace(chord("shift+down")))
    }

    @Test func `outside the layer and unmapped keys pass`() {
        var layer = CapsLayer()
        #expect(layer.decide(down(Self.w), capsHeld: false, map: Self.map).decision == .pass)
        #expect(layer.decide(down(Self.g), capsHeld: true, map: Self.map).decision == .pass)
    }

    @Test func `repeat keeps the layer after caps is released`() {
        var layer = CapsLayer()
        _ = layer.decide(down(Self.w), capsHeld: true, map: Self.map)
        #expect(layer.decide(down(Self.w, repeat: true), capsHeld: false, map: Self.map).decision == .replace(chord("up")))
        // 重新普通按下后就是普通的 w
        #expect(layer.decide(down(Self.w), capsHeld: false, map: Self.map).decision == .pass)
        #expect(layer.decide(down(Self.w, repeat: true), capsHeld: false, map: Self.map).decision == .pass)
    }

    @Test func `command runs once while held`() {
        var layer = CapsLayer()
        let map: [UInt16: LayerAction] = [Self.t: .command("finder.openTerminal")]
        let first = layer.decide(down(Self.t), capsHeld: true, map: map)
        #expect(first == CapsLayer.Result(decision: .consume, command: "finder.openTerminal"))
        let again = layer.decide(down(Self.t, repeat: true), capsHeld: true, map: map)
        #expect(again == CapsLayer.Result(decision: .consume, command: nil))
    }

    @Test func `first entry wins for duplicate keys`() {
        var settings = KeysSettings()
        settings.layer.append(LayerEntry(key: chord("w"), action: .keys(chord("home"))))
        #expect(settings.layerMap[Self.w] == .keys(chord("up")))
    }
}
