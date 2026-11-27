import CoreGraphics
import MAIOKit
import Observation

/// 按 App 改修饰键（ADR-0026）：前台 App 命中规则时，把"设备映射 ∘ 规则"写进每个键盘的服务属性，离开时写回设备映射。
/// 只改服务属性，不写偏好。映射要等修饰键全部松开再切，否则按住的修饰键松开时发出的是另一个键，会卡住。
/// 规则生效期间如果有新键盘接入（拔插、休眠重连等），会自动延迟补写映射，避开系统应用偏好的窗口。
@MainActor
@Observable
final class AppModifierController {
    @ObservationIgnored private let context: any FeatureContext
    @ObservationIgnored private let keyboards: any KeyboardHID
    @ObservationIgnored private let savedMapping: (DeviceKey) -> ModifierMapping?
    @ObservationIgnored private let isModifierHeld: () -> Bool
    @ObservationIgnored private let attachReapplyDelays: [Duration]
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
    @ObservationIgnored private var reapplyTask: Task<Void, Never>?
    @ObservationIgnored private var attachWatch: (any KeyboardAttachmentWatch)?
    /// 规则正在生效的 App（设置页显示）
    private(set) var activeBundleID: String?

    private static let modifierMask: CGEventFlags = [
        .maskCommand, .maskControl, .maskAlternate, .maskSecondaryFn, .maskShift,
    ]
    /// 键盘新接入后补写规则的等待间隔：第一次等系统偏好应用完，第二次兜底防止系统偏好较慢时覆盖
    private static let defaultAttachReapplyDelays: [Duration] = [.milliseconds(300), .milliseconds(1200)]

    convenience init(context: any FeatureContext, keyboards: HIDKeyboards) {
        let store = ModifierMappingStore(keyboards: keyboards)
        self.init(
            context: context,
            keyboards: keyboards,
            savedMapping: { store.savedMapping(for: $0) },
            isModifierHeld: { Self.modifiersHeld },
            attachReapplyDelays: Self.defaultAttachReapplyDelays,
        )
    }

    init(
        context: any FeatureContext,
        keyboards: any KeyboardHID,
        savedMapping: @escaping (DeviceKey) -> ModifierMapping?,
        isModifierHeld: @escaping () -> Bool,
        attachReapplyDelays: [Duration] = AppModifierController.defaultAttachReapplyDelays,
    ) {
        self.context = context
        self.keyboards = keyboards
        self.savedMapping = savedMapping
        self.isModifierHeld = isModifierHeld
        self.attachReapplyDelays = attachReapplyDelays
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
        pendingTask?.cancel()
        pendingTask = nil
        reapplyTask?.cancel()
        reapplyTask = nil
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
        attachWatch = keyboards.watchAttachments { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleKeyboardAttached()
            }
        }
    }

    private func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
        attachWatch?.cancel()
        attachWatch = nil
        reapplyTask?.cancel()
        reapplyTask = nil
    }

    /// 上次运行时 MAIO 可能在游戏前台时崩溃，留下改写过的映射：有偏好的键盘按偏好恢复
    private func healSavedKeyboards() {
        for device in keyboards.keyboards() {
            if let saved = savedMapping(device.key) {
                keyboards.apply(saved.pairs, to: device.key)
            }
        }
    }

    /// 规则生效期间检测到新键盘接入时，延迟重新应用规则（debounce 合并同一键盘的多个 HID 接口）
    private func handleKeyboardAttached() {
        guard applied != nil else { return }
        reapplyTask?.cancel()
        reapplyTask = Task { [weak self] in
            guard let self else { return }
            for delay in attachReapplyDelays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, applied != nil else { return }
                schedule(force: true)
            }
        }
    }

    /// 算出应该生效的规则；和现在一样就什么都不做（除非 force），否则等修饰键松开后再切
    private func schedule(force: Bool = false) {
        let wanted = AppModifierRules.swaps(for: frontmost, in: rules)
        pendingTask?.cancel()
        pendingTask = nil
        if wanted == nil {
            reapplyTask?.cancel()
            reapplyTask = nil
        }
        guard force || wanted != applied else {
            activeBundleID = wanted == nil ? nil : frontmost
            return
        }
        guard isModifierHeld() else {
            apply(wanted)
            return
        }
        pendingTask = Task { [weak self] in
            while !Task.isCancelled, self?.isModifierHeld() == true {
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
        let devices = keyboards.keyboards()
        if let swaps {
            var appliedCount = 0
            for device in devices {
                let base = base(of: device.key)
                let ok = keyboards.apply(AppModifierRules.compose(base, swaps).pairs, to: device.key)
                if ok {
                    appliedCount += 1
                    touched.insert(device.key)
                } else {
                    context.logger.error(
                        "按 App 改键：写入失败 \(device.name, privacy: .public)（\(device.key.vendorID)-\(device.key.productID)）",
                    )
                }
            }
            context.logger.info(
                "按 App 改键：\(self.frontmost ?? "", privacy: .public) 的规则已生效（\(appliedCount)/\(devices.count) 个键盘）",
            )
        } else {
            restore(devices)
        }
        applied = swaps
        activeBundleID = swaps == nil ? nil : frontmost
    }

    private func restore(_ devices: [KeyboardDevice]) {
        let connected = Dictionary(uniqueKeysWithValues: devices.map { ($0.key, $0) })
        for key in touched {
            guard let device = connected[key] else { continue }
            if !keyboards.apply(base(of: key).pairs, to: key) {
                context.logger.error(
                    "按 App 改键：恢复失败 \(device.name, privacy: .public)（\(key.vendorID)-\(key.productID)）",
                )
            }
        }
        if !touched.isEmpty {
            context.logger.info("按 App 改键：已恢复键盘的修饰键设置")
        }
        touched = []
    }

    /// 设备映射：偏好优先；没有偏好的用第一次改写之前的服务属性
    private func base(of device: DeviceKey) -> ModifierMapping {
        if let saved = savedMapping(device) {
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
