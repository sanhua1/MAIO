@testable import FeatureKeys
import MAIOTesting
import Testing

@MainActor
struct AppModifierControllerTests {
    private let game = "com.riotgames.LeagueofLegends.GameClient"
    private let otherApp = "com.apple.Finder"
    private let externalKey = DeviceKey(vendorID: 21320, productID: 30070)
    private let builtInKey = DeviceKey(vendorID: 1452, productID: 835)

    @Test func `reapplies swap when keyboard reconnects while rule is active`() async {
        let context = FakeFeatureContext(featureID: "keys")
        let hid = FakeKeyboardHID(devices: [
            KeyboardDevice(key: builtInKey, name: "BuiltIn", isBuiltIn: true),
            KeyboardDevice(key: externalKey, name: "Makey75", isBuiltIn: false),
        ])
        let controller = AppModifierController(
            context: context,
            keyboards: hid,
            savedMapping: { _ in nil },
            isModifierHeld: { false },
            attachReapplyDelays: [.milliseconds(10)],
        )
        let rule = AppModifierRule(bundleID: game, name: "LoL", swaps: ModifierSwap.commandControl)
        controller.update([rule])

        // 切入游戏，两把键盘都应写入对调映射
        context.fakeEvents.setFrontmost(game)
        try? await Task.sleep(for: .milliseconds(30))
        let swapped = AppModifierRules.compose(ModifierMapping(pairs: []), [.command: .control, .control: .command]).pairs
        #expect(Set(hid.currentPairs(of: externalKey) ?? []) == Set(swapped))
        #expect(controller.activeBundleID == game)

        // 模拟游戏中拔插外接键盘：重连后映射被系统重置为空，然后触发接入回调
        hid.resetDevice(externalKey)
        #expect(hid.currentPairs(of: externalKey)?.isEmpty == true)
        hid.simulateAttach()
        try? await Task.sleep(for: .milliseconds(50))

        // 自动补写回来
        #expect(Set(hid.currentPairs(of: externalKey) ?? []) == Set(swapped))

        // 离开游戏，恢复为空映射
        context.fakeEvents.setFrontmost(otherApp)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(hid.currentPairs(of: externalKey)?.isEmpty == true)
        #expect(controller.activeBundleID == nil)

        controller.stop()
        #expect(hid.watchCancelled)
    }

    @Test func `applies swap to keyboard reconnected before entering game`() async {
        let context = FakeFeatureContext(featureID: "keys")
        let hid = FakeKeyboardHID(devices: [
            KeyboardDevice(key: builtInKey, name: "BuiltIn", isBuiltIn: true),
        ])
        let controller = AppModifierController(
            context: context,
            keyboards: hid,
            savedMapping: { _ in nil },
            isModifierHeld: { false },
            attachReapplyDelays: [.milliseconds(10)],
        )
        let rule = AppModifierRule(bundleID: game, name: "LoL", swaps: ModifierSwap.commandControl)
        controller.update([rule])

        // 进游戏前新插上外接键盘：不在游戏前台，不应写入对调
        hid.devices.append(KeyboardDevice(key: externalKey, name: "Makey75", isBuiltIn: false))
        hid.simulateAttach()
        try? await Task.sleep(for: .milliseconds(40))
        #expect(hid.currentPairs(of: externalKey)?.isEmpty == true)

        // 进入游戏，应该立即对新插上的外接键盘生效
        context.fakeEvents.setFrontmost(game)
        try? await Task.sleep(for: .milliseconds(30))
        let swapped = AppModifierRules.compose(ModifierMapping(pairs: []), [.command: .control, .control: .command]).pairs
        #expect(Set(hid.currentPairs(of: externalKey) ?? []) == Set(swapped))

        controller.stop()
    }
}

private final class FakeWatch: KeyboardAttachmentWatch {
    var onCancel: () -> Void
    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel()
    }
}

private final class FakeKeyboardHID: KeyboardHID {
    var isAvailable = true
    var devices: [KeyboardDevice]
    var pairsByDevice: [DeviceKey: [MappingPair]] = [:]
    var onAttach: (@Sendable () -> Void)?
    var watchCancelled = false

    init(devices: [KeyboardDevice]) {
        self.devices = devices
    }

    func keyboards() -> [KeyboardDevice] {
        devices
    }

    func currentPairs(of device: DeviceKey) -> [MappingPair]? {
        guard devices.contains(where: { $0.key == device }) else { return nil }
        return pairsByDevice[device] ?? []
    }

    @discardableResult
    func apply(_ pairs: [MappingPair], to device: DeviceKey) -> Bool {
        guard devices.contains(where: { $0.key == device }) else { return false }
        pairsByDevice[device] = pairs
        return true
    }

    func watchAttachments(_ onAttach: @escaping @Sendable () -> Void) -> (any KeyboardAttachmentWatch)? {
        self.onAttach = onAttach
        return FakeWatch { [weak self] in
            self?.watchCancelled = true
            self?.onAttach = nil
        }
    }

    func resetDevice(_ device: DeviceKey) {
        pairsByDevice[device] = []
    }

    func simulateAttach() {
        onAttach?()
    }
}
