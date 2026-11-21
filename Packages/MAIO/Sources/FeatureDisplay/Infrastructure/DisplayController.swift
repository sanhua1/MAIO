import AppKit
import CoreGraphics
import MAIOKit
import Observation
import os

/// 外接显示器的亮度、音量控制：扫描显示器、决定媒体键交给谁、步进、写 DDC、弹浮窗。
@MainActor
@Observable
final class DisplayController {
    struct Entry: Identifiable {
        var info: ControllableDisplay
        let channel: DDCChannel
        var brightness: VCPValue?
        var volume: VolumeState?
        /// 上次从显示器读到或写给显示器的时间。太久没碰就重新读（用户可能用显示器自己的按钮调过）
        var touched: [VCPCode: ContinuousClock.Instant] = [:]

        var id: CGDirectDisplayID {
            info.id
        }
    }

    private(set) var displays: [Entry] = []
    private(set) var output: AudioOutputInfo?
    /// 音量键当前调的显示器（声音从它出来、系统调不了）；菜单里只给它显示音量条
    private(set) var volumeDisplay: CGDirectDisplayID?
    private(set) var isScanning = false

    @ObservationIgnored let filter: DisplayMediaKeyFilter
    @ObservationIgnored private let keys: AsyncStream<(MediaKeyEvent, CGDirectDisplayID)>
    @ObservationIgnored private let hud = LevelHUD()
    @ObservationIgnored private let audio = AudioOutputMonitor()
    @ObservationIgnored private let watcher = DisplayWatcher()
    @ObservationIgnored private var settings: DisplaySettings
    @ObservationIgnored private let logger: Logger
    @ObservationIgnored private var keyTask: Task<Void, Never>?
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    /// 超过这么久没碰，按键前先从显示器重新读当前值
    private static let staleAfter: Duration = .seconds(5)

    init(settings: DisplaySettings, logger: Logger) {
        self.settings = settings
        self.logger = logger
        let (stream, continuation) = AsyncStream.makeStream(
            of: (MediaKeyEvent, CGDirectDisplayID).self, bufferingPolicy: .bufferingNewest(32),
        )
        keys = stream
        filter = DisplayMediaKeyFilter { event, display in continuation.yield((event, display)) }
    }

    func start() {
        let keys = keys
        // 按键逐个处理：前一个读完、写完再处理下一个，不会两次按键同时去读显示器
        keyTask = Task { [weak self] in
            for await (event, display) in keys {
                await self?.handle(event, on: display)
            }
        }
        audio.start { [weak self] in self?.refreshTargets() }
        watcher.start { [weak self] delay in self?.scheduleScan(after: delay) }
        scheduleScan(after: .zero)
    }

    func stop() {
        keyTask?.cancel()
        scanTask?.cancel()
        audio.stop()
        watcher.stop()
        hud.hide()
        filter.update(.init())
    }

    func apply(_ settings: DisplaySettings) {
        self.settings = settings
        refreshTargets()
    }

    // MARK: 扫描

    /// 插拔、唤醒后显示器要过一会儿才能响应 DDC，所以延迟扫描；连续触发只扫最后一次。
    /// 有读失败（不是"不支持"）的就过一会儿再扫，最多重试 `maxRetries` 次，间隔越来越长
    func scheduleScan(after delay: Duration, retry: Int = 0) {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            let hadFailure = await rescan()
            guard hadFailure, retry < Self.maxRetries, !Task.isCancelled else { return }
            logger.info("有显示器这次没读到，\(retry + 1) 次重试")
            scheduleScan(after: .seconds(2 * (retry + 1)), retry: retry + 1)
        }
    }

    private static let maxRetries = 5

    /// 返回是否有读失败
    private func rescan() async -> Bool {
        isScanning = true
        defer { isScanning = false }
        var found: [Entry] = []
        var hadFailure = false
        for display in DisplayScanner.scan() {
            let (entry, failed) = await scanEntry(display, old: displays.first { $0.id == display.id })
            hadFailure = hadFailure || failed
            if let entry {
                found.append(entry)
            }
        }
        guard !Task.isCancelled else { return false }
        displays = found
        let summary = found.map { entry in
            "\(entry.info.name)#\(entry.id) 亮度 \(entry.brightness?.current ?? -1) 音量 \(entry.volume?.value.current ?? -1)"
        }
        logger.info("扫描外接显示器：\(summary.isEmpty ? "无" : summary.joined(separator: "；"), privacy: .public)")
        refreshTargets()
        return hadFailure
    }

    /// 读一台显示器的亮度和音量。没读到（不是"不支持"）时沿用上次的结果，并让下次按键先重新读
    private func scanEntry(_ display: ScannedDisplay, old: Entry?) async -> (Entry?, failed: Bool) {
        let brightness = await display.channel.read(.brightness)
        let volume = await display.channel.read(.volume)
        let now = ContinuousClock.now
        var entry = Entry(
            info: ControllableDisplay(id: display.id, name: display.name, supportsBrightness: false, supportsVolume: false),
            channel: display.channel,
        )
        switch brightness {
        case let .value(value):
            entry.brightness = value
            entry.touched[.brightness] = now
        case .failed: entry.brightness = old?.brightness
        case .unsupported: break
        }
        switch volume {
        case let .value(value):
            // 保留静音状态（静音时显示器音量是 0，不能当成用户把音量调到了 0）
            var state = old?.volume ?? VolumeState(value: value)
            state.sync(value)
            entry.volume = state
            entry.touched[.volume] = now
        case .failed: entry.volume = old?.volume
        case .unsupported: break
        }
        entry.info.supportsBrightness = entry.brightness != nil
        entry.info.supportsVolume = entry.volume != nil
        let failed = brightness == .failed || volume == .failed
        if failed {
            logger.warning(
                "\(display.name, privacy: .public) 读取失败：亮度 \(String(describing: brightness), privacy: .public)，音量 \(String(describing: volume), privacy: .public)",
            )
        }
        let usable = entry.info.supportsBrightness || entry.info.supportsVolume
        return (usable ? entry : nil, failed)
    }

    func refreshTargets() {
        output = AudioOutputMonitor.current()
        let infos = displays.map(\.info)
        let snapshot = DisplayMediaKeyFilter.Snapshot(
            volumeDisplay: settings.controlVolume ? VolumeTargeting.display(for: output, among: infos) : nil,
            brightnessDisplays: settings.controlBrightness ? Set(infos.filter(\.supportsBrightness).map(\.id)) : [],
        )
        filter.update(snapshot)
        volumeDisplay = snapshot.volumeDisplay
        let outputName = output.map { "\($0.name)（系统\($0.canSetVolume ? "能" : "不能")调）" } ?? "无"
        logger.info(
            "声音输出 \(outputName, privacy: .public)，音量键 → \(snapshot.volumeDisplay.map { "#\($0)" } ?? "系统", privacy: .public)，亮度键 → \(snapshot.brightnessDisplays.map { "#\($0)" }.joined(separator: ","), privacy: .public)",
        )
    }

    // MARK: 菜单滑块

    /// 菜单里显示的显示器：能调亮度的，或者是当前音量键调的那台
    var menuDisplays: [Entry] {
        displays.filter { $0.brightness != nil || hasMenuVolume($0) }
    }

    func hasMenuVolume(_ entry: Entry) -> Bool {
        entry.id == volumeDisplay && entry.volume != nil
    }

    func setBrightness(_ fraction: Double, on id: CGDirectDisplayID) {
        guard let index = displays.firstIndex(where: { $0.id == id }), var value = displays[index].brightness else {
            return
        }
        value.current = Int((min(max(fraction, 0), 1) * Double(value.maximum)).rounded())
        guard value != displays[index].brightness else { return }
        displays[index].brightness = value
        displays[index].touched[.brightness] = .now
        displays[index].channel.write(.brightness, value: value.current)
    }

    /// 拖音量条：静音时一拖就取消静音
    func setVolume(_ fraction: Double, on id: CGDirectDisplayID) {
        guard let index = displays.firstIndex(where: { $0.id == id }), var state = displays[index].volume else {
            return
        }
        let value = Int((min(max(fraction, 0), 1) * Double(state.value.maximum)).rounded())
        guard value != state.value.current || state.isMuted else { return }
        state.set(value)
        displays[index].volume = state
        displays[index].touched[.volume] = .now
        displays[index].channel.write(.volume, value: value)
    }

    /// 打开菜单时：把太久没碰的亮度、音量重新读一遍
    func refreshMenuLevels() {
        Task { [weak self] in
            guard let self else { return }
            for entry in displays {
                if entry.info.supportsBrightness {
                    _ = await fresh(.brightness, on: entry.id)
                }
                if hasMenuVolume(entry) {
                    _ = await fresh(.volume, on: entry.id)
                }
            }
        }
    }

    // MARK: 媒体键

    private func handle(_ event: MediaKeyEvent, on id: CGDirectDisplayID) async {
        logger.debug("媒体键 \(String(describing: event.key), privacy: .public) → #\(id)")
        // ⌥ + 音量 / 亮度键：和系统一样打开对应的设置页
        if event.modifiers == .option {
            if !event.isRepeat {
                SystemSettingsPage.open(event.key.isVolume ? .sound : .displays)
            }
            return
        }
        let fine = event.modifiers.isSuperset(of: [.option, .shift])
        switch event.key {
        case .volumeUp, .volumeDown: await stepVolume(on: id) { $0.step(up: event.key == .volumeUp, fine: fine) }
        case .mute: if !event.isRepeat {
                await stepVolume(on: id) { $0.toggleMute() }
            }
        case .brightnessUp, .brightnessDown: await stepBrightness(on: id, up: event.key == .brightnessUp, fine: fine)
        }
    }

    private func stepVolume(on id: CGDirectDisplayID, _ change: (inout VolumeState) -> Int) async {
        guard await fresh(.volume, on: id), let index = displays.firstIndex(where: { $0.id == id }),
              var state = displays[index].volume else { return }
        let value = change(&state)
        displays[index].volume = state
        displays[index].touched[.volume] = .now
        displays[index].channel.write(.volume, value: value)
        let fraction = Double(state.value.current) / Double(state.value.maximum)
        hud.show(.volume(muted: state.isMuted), fraction: fraction, on: id)
    }

    private func stepBrightness(on id: CGDirectDisplayID, up: Bool, fine: Bool) async {
        guard await fresh(.brightness, on: id), let index = displays.firstIndex(where: { $0.id == id }),
              var value = displays[index].brightness else { return }
        value.current = LevelStepper.step(value, up: up, fine: fine)
        displays[index].brightness = value
        displays[index].touched[.brightness] = .now
        displays[index].channel.write(.brightness, value: value.current)
        let fraction = Double(value.current) / Double(value.maximum)
        hud.show(.brightness, fraction: fraction, on: id)
    }

    /// 需要时从显示器重新读当前值。返回 false 表示这台显示器没有这个值（读不到、也没有缓存）
    private func fresh(_ code: VCPCode, on id: CGDirectDisplayID) async -> Bool {
        guard let entry = displays.first(where: { $0.id == id }) else { return false }
        let isStale = entry.touched[code].map { ContinuousClock.now - $0 > Self.staleAfter } ?? true
        guard isStale else { return true }
        let value = await entry.channel.read(code).value
        guard let index = displays.firstIndex(where: { $0.id == id }) else { return false }
        if let value {
            displays[index].touched[code] = .now
            switch code {
            case .brightness: displays[index].brightness = value
            case .volume:
                if displays[index].volume == nil {
                    displays[index].volume = VolumeState(value: value)
                } else {
                    displays[index].volume?.sync(value)
                }
            }
        }
        return code == .brightness ? displays[index].brightness != nil : displays[index].volume != nil
    }
}
