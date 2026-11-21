@testable import FeatureDisplay
import MAIOKit
import MAIOTesting
import Testing

@MainActor
struct DisplayFeatureTests {
    @Test func `activate registers media key filter and deactivate stops`() async throws {
        let context = FakeFeatureContext(featureID: "display")
        let feature = DisplayFeature(context: context)
        try await feature.activate()
        #expect(context.fakeInput.mediaKeyFilters.count == 1)
        // 还没扫描到显示器时，媒体键全部交给系统
        let filter = try #require(context.fakeInput.mediaKeyFilters.values.first)
        #expect(filter.process(MediaKeyEvent(key: .volumeUp)) == .pass)
        #expect(filter.process(MediaKeyEvent(key: .brightnessUp)) == .pass)
        await feature.deactivate()
    }
}

struct DDCPacketTests {
    @Test func `get request matches known bytes`() {
        // 0x6E ^ 0x51 ^ 0x82 ^ 0x01 ^ 0x10 = 0xAC
        #expect(DDCPacket.getRequest(.brightness) == [0x82, 0x01, 0x10, 0xAC])
    }

    @Test func `set request encodes value and checksum`() {
        let packet = DDCPacket.setRequest(.volume, value: 300)
        #expect(Array(packet.prefix(5)) == [0x84, 0x03, 0x62, 0x01, 0x2C])
        #expect(packet[5] == packet.prefix(5).reduce(0x6E ^ 0x51, ^))
    }

    @Test func `parses real reply from monitor`() {
        // 实测：MAG 272U E16 的亮度 40/100、音量 100/100
        let brightness: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x28, 0xE8]
        let volume: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x62, 0x00, 0x00, 0x64, 0x00, 0x64, 0xD6]
        #expect(DDCPacket.parse(brightness, for: .brightness) == .value(VCPValue(current: 40, maximum: 100)))
        #expect(DDCPacket.parse(volume, for: .volume) == .value(VCPValue(current: 100, maximum: 100)))
    }

    @Test func `unsupported is distinguished from failure`() {
        // 结果字节 01：显示器明确回复不支持
        let body: [UInt8] = [0x6E, 0x88, 0x02, 0x01, 0x62, 0x00, 0x00, 0x64, 0x00, 0x64]
        #expect(DDCPacket.parse(body + [body.reduce(UInt8(0x50), ^)], for: .volume) == .unsupported)
        // 全 0（显示器刚唤醒时常见）是读失败，不是不支持
        #expect(DDCPacket.parse([UInt8](repeating: 0, count: 11), for: .volume) == .failed)
    }

    @Test func `rejects wrong code and bad checksum`() {
        var corrupted: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x28, 0xE8]
        #expect(DDCPacket.parse(corrupted, for: .volume) == .failed)
        corrupted[10] = 0x00
        #expect(DDCPacket.parse(corrupted, for: .brightness) == .failed)
        #expect(DDCPacket.parse([0x6E], for: .brightness) == .failed)
    }
}

struct LevelStepperTests {
    private func step(_ current: Int, up: Bool, fine: Bool = false) -> Int {
        LevelStepper.step(VCPValue(current: current, maximum: 100), up: up, fine: fine)
    }

    @Test func `snaps to sixteenth grid`() {
        #expect(step(40, up: true) == 44) // 6.4 格 → 第 7 格 43.75
        #expect(step(40, up: false) == 38) // → 第 6 格 37.5
        #expect(step(50, up: true) == 56) // 正好第 8 格 → 第 9 格 56.25
        #expect(step(50, up: false) == 44)
    }

    @Test func `clamps at ends`() {
        #expect(step(100, up: true) == 100)
        #expect(step(0, up: false) == 0)
        #expect(step(98, up: true) == 100)
    }

    @Test func `fine step is quarter chiclet`() {
        #expect(step(50, up: true, fine: true) == 52) // 51.5625
        #expect(step(50, up: false, fine: true) == 48)
    }

    @Test func `repeated steps reach every chiclet without stalling`() {
        var value = 0
        for _ in 0 ..< 16 {
            let next = step(value, up: true)
            #expect(next > value)
            value = next
        }
        #expect(value == 100)
    }
}

struct VolumeStateTests {
    @Test func `dragging the slider unmutes`() {
        var state = VolumeState(value: VCPValue(current: 60, maximum: 100))
        _ = state.toggleMute()
        state.set(30)
        #expect(!state.isMuted)
        #expect(state.value.current == 30)
        state.set(250)
        #expect(state.value.current == 100)
    }

    @Test func `mute remembers and restores`() {
        var state = VolumeState(value: VCPValue(current: 60, maximum: 100))
        #expect(state.toggleMute() == 0)
        #expect(state.isMuted)
        #expect(state.toggleMute() == 60)
        #expect(!state.isMuted)
    }

    @Test func `step while muted unmutes first`() {
        var state = VolumeState(value: VCPValue(current: 50, maximum: 100))
        _ = state.toggleMute()
        #expect(state.step(up: true, fine: false) == 56)
        #expect(!state.isMuted)
    }

    @Test func `mute at zero restores to one chiclet`() {
        var state = VolumeState(value: VCPValue(current: 0, maximum: 100))
        _ = state.toggleMute()
        #expect(state.toggleMute() == 6)
    }

    @Test func `sync keeps mute only while monitor still at zero`() {
        var state = VolumeState(value: VCPValue(current: 70, maximum: 100))
        _ = state.toggleMute()
        state.sync(VCPValue(current: 0, maximum: 100))
        #expect(state.isMuted)
        state.sync(VCPValue(current: 30, maximum: 100))
        #expect(!state.isMuted)
        #expect(state.value.current == 30)
    }
}

struct TargetingTests {
    private let monitor = ControllableDisplay(id: 2, name: "MAG 272U E16", supportsBrightness: true, supportsVolume: true)

    @Test func `system controllable output goes to system`() {
        let headset = AudioOutputInfo(name: "G433 Gaming Headset", isDisplayTransport: false, canSetVolume: true)
        #expect(VolumeTargeting.display(for: headset, among: [monitor]) == nil)
    }

    @Test func `display output matches by name`() {
        let output = AudioOutputInfo(name: "MAG 272U E16", isDisplayTransport: true, canSetVolume: false)
        let other = ControllableDisplay(id: 3, name: "Other", supportsBrightness: true, supportsVolume: true)
        #expect(VolumeTargeting.display(for: output, among: [other, monitor]) == 2)
    }

    @Test func `falls back to the only volume display when name differs`() {
        let output = AudioOutputInfo(name: "改过名的显示器", isDisplayTransport: true, canSetVolume: false)
        #expect(VolumeTargeting.display(for: output, among: [monitor]) == 2)
        let noVolume = ControllableDisplay(id: 2, name: "X", supportsBrightness: true, supportsVolume: false)
        #expect(VolumeTargeting.display(for: output, among: [noVolume]) == nil)
        #expect(VolumeTargeting.display(for: nil, among: [monitor]) == nil)
    }

    @Test func `matches services to screens by identity`() {
        let screens = [
            DisplayMatching.Screen(id: 2, vendor: 0x0DC4, model: 0x8CD7, serial: 16_843_009, name: "MAG 272U E16"),
            DisplayMatching.Screen(id: 5, vendor: 0x10AC, model: 0x4321, serial: 7, name: "DELL"),
        ]
        let services = [
            DisplayMatching.Service(index: 0, vendor: 0x10AC, product: 0x4321, serial: 7, name: "DELL"),
            DisplayMatching.Service(index: 1, vendor: 3524, product: 36055, serial: 16_843_009, name: "MAG 272U E16"),
        ]
        #expect(DisplayMatching.match(services: services, screens: screens) == [2: 1, 5: 0])
    }

    @Test func `single screen and service pair directly`() {
        let screen = DisplayMatching.Screen(id: 9, vendor: 1, model: 2, serial: 3, name: "A")
        let service = DisplayMatching.Service(index: 0)
        #expect(DisplayMatching.match(services: [service], screens: [screen]) == [9: 0])
    }
}
