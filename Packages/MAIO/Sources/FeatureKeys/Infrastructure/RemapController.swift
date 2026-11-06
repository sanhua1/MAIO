import Foundation
import MAIOKit

/// 把设置落到系统上：HID 层的全局映射（Caps → 无操作、单键换单键）、Caps 的按下 / 松开、
/// 按键过滤器（Caps 层 + 全局组合键 / 命令）、鼠标按钮过滤器。设置变化时增量更新。
@MainActor
@Observable
final class RemapController {
    enum CapsStatus: Equatable {
        case off
        case on
        /// 没有输入监控权限，读不到 Caps 的按下 / 松开（Caps 已恢复原样）
        case noInputMonitoring
        case failed(String)
    }

    @ObservationIgnored private let context: any FeatureContext
    @ObservationIgnored private let mapping: GlobalKeyMapping
    @ObservationIgnored private var monitor: CapsKeyMonitor?
    @ObservationIgnored private var keyFilter: (filter: KeyRemapFilter, token: FilterToken)?
    @ObservationIgnored private var buttonFilter: (filter: MouseRemapFilter, token: FilterToken)?
    @ObservationIgnored private let continuation: AsyncStream<CommandID>.Continuation
    @ObservationIgnored private var commandTask: Task<Void, Never>?
    private(set) var capsStatus = CapsStatus.off
    /// HID 层的映射没写进去
    private(set) var mappingFailed = false

    init(context: any FeatureContext, keyboards: HIDKeyboards) {
        self.context = context
        mapping = GlobalKeyMapping(keyboards: keyboards)
        let (commands, continuation) = AsyncStream<CommandID>.makeStream(bufferingPolicy: .bufferingNewest(8))
        self.continuation = continuation
        commandTask = Task { [context] in
            for await id in commands {
                do {
                    _ = try await context.commands.perform(id, arguments: [:])
                } catch {
                    context.overlay.showError(error.localizedDescription)
                }
            }
        }
    }

    func apply(_ settings: KeysSettings) {
        let caps = updateCapsMonitor(enabled: settings.capsLayerEnabled)
        var pairs = GlobalRemaps.hidPairs(settings.remaps)
        if caps != nil {
            pairs.removeAll { $0.source == GlobalKeyMapping.capsLock.source }
            pairs.append(GlobalKeyMapping.capsLock)
        }
        mappingFailed = !mapping.apply(pairs)
        if caps != nil, mappingFailed {
            stopCapsMonitor()
            capsStatus = .failed("没能把 Caps 设成无操作")
        }
        let config = KeyRemapFilter.Config(
            caps: monitor, layer: monitor == nil ? [:] : settings.layerMap, global: GlobalRemaps.tapMap(settings.remaps),
        )
        updateKeyFilter(config)
        updateButtonFilter(GlobalRemaps.buttonMap(settings.mouseRemaps))
    }

    func stop() {
        commandTask?.cancel()
        commandTask = nil
        continuation.finish()
        updateKeyFilter(KeyRemapFilter.Config())
        updateButtonFilter([:])
        stopCapsMonitor()
        mapping.removeAll()
    }

    // MARK: - 私有

    /// 打开 / 关闭 Caps 的监听；返回当前的监听（没打开或失败时 nil）
    private func updateCapsMonitor(enabled: Bool) -> CapsKeyMonitor? {
        guard enabled else {
            stopCapsMonitor()
            return nil
        }
        if let monitor {
            return monitor
        }
        let monitor = CapsKeyMonitor()
        let opened = monitor.start()
        guard opened == kIOReturnSuccess else {
            context.logger.error("Caps 分层：打开键盘输入失败 \(opened)")
            capsStatus = opened == kIOReturnNotPermitted ? .noInputMonitoring : .failed("打开键盘输入失败（\(opened)）")
            return nil
        }
        self.monitor = monitor
        capsStatus = .on
        return monitor
    }

    private func stopCapsMonitor() {
        monitor?.stop()
        monitor = nil
        capsStatus = .off
    }

    private func updateKeyFilter(_ config: KeyRemapFilter.Config) {
        let needed = config.caps != nil || !config.global.isEmpty
        switch (keyFilter, needed) {
        case let (current?, true): current.filter.update(config)
        case let (current?, false):
            context.input.removeFilter(current.token)
            keyFilter = nil
        case (nil, true):
            let filter = KeyRemapFilter(config: config, continuation: continuation)
            keyFilter = (filter, context.input.registerKeyFilter(filter))
        case (nil, false): break
        }
    }

    private func updateButtonFilter(_ map: [Int: LayerAction]) {
        switch (buttonFilter, !map.isEmpty) {
        case let (current?, true): current.filter.update(map)
        case let (current?, false):
            context.input.removeFilter(current.token)
            buttonFilter = nil
        case (nil, true):
            let filter = MouseRemapFilter(map: map, continuation: continuation)
            buttonFilter = (filter, context.input.registerButtonFilter(filter))
        case (nil, false): break
        }
    }
}
