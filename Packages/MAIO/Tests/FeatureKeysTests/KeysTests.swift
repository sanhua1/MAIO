@testable import FeatureKeys
import Testing

struct ModifierMappingTests {
    /// 系统设置实际写下的映射（自带键盘改成 ⌘ ⌃ Fn ⌥：🌐→⌘、⌥→🌐、⌘→⌥）
    static let systemPairs: [MappingPair] = [
        (30_064_771_303, 30_064_771_302), (30_064_771_299, 30_064_771_298), (280_379_760_050_179, 30_064_771_299),
        (30_064_771_302, 1_095_216_660_483), (1_095_216_660_483, 30_064_771_303), (30_064_771_298, 1_095_216_660_483),
    ].map { MappingPair(source: $0.0, destination: $0.1) }

    @Test func `reads what system settings wrote`() {
        let mapping = ModifierMapping(pairs: Self.systemPairs)
        #expect(mapping.target(for: .globe) == .command)
        #expect(mapping.target(for: .option) == .globe)
        #expect(mapping.target(for: .command) == .option)
        #expect(mapping.target(for: .control) == .control)
        #expect(mapping.target(for: .capsLock) == .capsLock)
    }

    @Test func `writes the same pairs as system settings`() {
        var mapping = ModifierMapping(pairs: [])
        mapping.set(.globe, to: .command)
        mapping.set(.option, to: .globe)
        mapping.set(.command, to: .option)
        #expect(Set(mapping.pairs) == Set(Self.systemPairs))
    }

    @Test func `setting back to itself removes the mapping`() {
        var mapping = ModifierMapping(pairs: Self.systemPairs)
        for key in ModifierKey.allCases {
            mapping.set(key, to: ModifierTarget(key))
        }
        #expect(mapping.isDefault)
        #expect(mapping.pairs.isEmpty)
    }

    @Test func `keeps pairs it does not understand`() {
        let shift = MappingPair(source: HIDUsage.keyboard(0xE1), destination: HIDUsage.keyboard(0xE0))
        let odd = MappingPair(source: HIDUsage.keyboard(0x39), destination: HIDUsage.keyboard(0x04))
        var mapping = ModifierMapping(pairs: [shift, odd])
        #expect(mapping.target(for: .capsLock) == .capsLock)
        #expect(Set(mapping.pairs) == [shift, odd])
        // 用户改了 Caps，旧的那条 Caps 映射被替换，别的保留
        mapping.set(.capsLock, to: .escape)
        #expect(Set(mapping.pairs) == [shift, MappingPair(source: HIDUsage.keyboard(0x39), destination: HIDUsage.keyboard(0x29))])
    }

    @Test func `built in keyboard is listed first`() {
        let devices = KeyboardDevice.sorted([
            KeyboardDevice(key: DeviceKey(vendorID: 1, productID: 1), name: "Makey75", isBuiltIn: false),
            KeyboardDevice(key: DeviceKey(vendorID: 1452, productID: 835), name: "Apple Internal Keyboard", isBuiltIn: true),
        ])
        #expect(devices.map(\.displayName) == ["Mac 自带键盘", "Makey75"])
        #expect(devices[0].key.preferenceKey == "com.apple.keyboard.modifiermapping.1452-835-0")
    }
}
