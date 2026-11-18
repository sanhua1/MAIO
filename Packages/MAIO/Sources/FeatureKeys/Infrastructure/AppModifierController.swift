import CoreGraphics
import MAIOKit
import Observation

/// 按 App 改修饰键（ADR-0026）：前台 App 命中规则时，把"设备映射 ∘ 规则"写进每个键盘的服务属性，离开时写回设备映射。
/// 只改服务属性，不写偏好。映射要等修饰键全部松开再切，否则按住的修饰键松开时发出的是另一个键，会卡住。
@MainActor
@Observable
final class AppModifierController {
    @ObservationIgnored private let context: any FeatureContext
    @ObservationIgnored private let keyboards: HIDKeyboards
    @ObservationIgnored private var rules: [AppModifierRule] = []
    @ObservationIgnored private var frontmost: String?
    /// 现在写在键盘上的规则（nil = 设备映射）
    @ObservationIgnored private var applied: [ModifierKey: ModifierTarget]?
    /// 没有偏好的键盘：第一次改写之前的服务属性
    @ObservationIgnored private var originals: [DeviceKey: ModifierMapping] = [:]
    /// 改写过的键盘（离开时要写回）
    @ObservationIgnored private var touched: Set<DeviceKey> = []
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var pendingTask: Task<Void, Never>?
    /// 规则正在生效的 App（设置页显示）
    private(set) var activeBundleID: String?

    private static let modifierMask: CGEventFlags = [
        .maskCommand, .maskControl, .maskAlternate, .maskSecondaryFn, .maskShift,
    ]

    init(context: any FeatureContext, keyboards: HIDKeyboards) {
        self.context = context
        self.keyboards = keyboards
    }

    func update(_ rules: [AppModifierRule]) {
        let wasEmpty = self.rules.isEmpty
        self.rules = rules
        if rules.isEmpty {
            stopWatching()
        } else if watchTask == nil {
            startWatching(healFirst: wasEmpty)
        }
        schedule()
    }

    /// 退出 / 功能关闭：立即写回（来不及等修饰键松开）
    func stop() {
        stopWatching()
        rules = []
        apply(nil)
    }

    // MARK: - 私有

    private func startWatching(healFirst: Bool) {
        if healFirst {
            healSavedKeyboards()
        }
        frontmost = context.events.frontmostBundleID
        let changes = context.events.frontmostApplicationChanges()
        watchTask = Task { [weak self] in
            for await bundleID in changes {
                self?.frontmost = bundleID
                self?.schedule()
            }
        }
    }

    private func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
    }

    /// 上次运行时 MAIO 可能在游戏前台时崩溃，留下改写过的映射：有偏好的键盘按偏好恢复
    private func healSavedKeyboards() {
        let store = ModifierMappingStore(keyboards: keyboards)
        for device in keyboards.keyboards() {
            if let saved = store.savedMapping(for: device.key) {
                keyboards.apply(saved.pairs, to: device.key)
            }
        }
    }

    /// 算出应该生效的规则；和现在一样就什么都不做，否则等修饰键松开后再切
    private func schedule() {
        let wanted = AppModifierRules.swaps(for: frontmost, in: rules)
        pendingTask?.cancel()
        pendingTask = nil
        guard wanted != applied else {
            activeBundleID = wanted == nil ? nil : frontmost
            return
        }
        guard Self.modifiersHeld else {
            apply(wanted)
            return
        }
        pendingTask = Task { [weak self] in
            while !Task.isCancelled, Self.modifiersHeld {
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard !Task.isCancelled, let self else { return }
            pendingTask = nil
            apply(AppModifierRules.swaps(for: frontmost, in: rules))
        }
    }

    private static var modifiersHeld: Bool {
        !CGEventSource.flagsState(.hidSystemState).isDisjoint(with: modifierMask)
    }

    private func apply(_ swaps: [ModifierKey: ModifierTarget]?) {
        let store = ModifierMappingStore(keyboards: keyboards)
        let devices = keyboards.keyboards().map(\.key)
        if let swaps {
            for device in devices {
                let base = base(of: device, store: store)
                keyboards.apply(AppModifierRules.compose(base, swaps).pairs, to: device)
                touched.insert(device)
            }
            context.logger.info("按 App 改键：\(self.frontmost ?? "", privacy: .public) 的规则已生效")
        } else {
            for device in touched where devices.contains(device) {
                keyboards.apply(base(of: device, store: store).pairs, to: device)
            }
            if !touched.isEmpty {
                context.logger.info("按 App 改键：已恢复键盘的修饰键设置")
            }
            touched = []
        }
        applied = swaps
        activeBundleID = swaps == nil ? nil : frontmost
    }

    /// 设备映射：偏好优先；没有偏好的用第一次改写之前的服务属性
    private func base(of device: DeviceKey, store: ModifierMappingStore) -> ModifierMapping {
        if let saved = store.savedMapping(for: device) {
            return saved
        }
        if let original = originals[device] {
            return original
        }
        let current = ModifierMapping(pairs: keyboards.currentPairs(of: device) ?? [])
        originals[device] = current
        return current
    }
}
