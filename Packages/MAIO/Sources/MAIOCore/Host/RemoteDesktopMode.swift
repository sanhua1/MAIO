import Foundation
import Observation
import os

/// 远程桌面设置（config/remote-desktop.json，ADR-0027）。
public struct RemoteDesktopSettings: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    /// 远程桌面 App 在前台时，把 MAIO 的快捷键和改键让给它
    public var enabled = true
    /// 算作远程桌面的 App（bundle ID）
    public var bundleIDs: [String] = Self.defaultBundleIDs

    static let path = "config/remote-desktop.json"

    /// 默认名单。只有 UU 远程、屏幕共享在本机核实过 bundle ID，其余按公开资料填写。
    public static let defaultBundleIDs = [
        "com.netease.uuremote", // 网易 UU 远程
        "com.youqu.todesk.mac", // ToDesk
        "com.oray.sunlogin.macclient", // 向日葵
        "com.microsoft.rdc.macos", // Microsoft 远程桌面 / Windows App
        "tv.parsec.www", // Parsec
        "com.teamviewer.TeamViewer",
        "com.philandro.anydesk",
        "com.carriez.rustdesk",
        "com.apple.ScreenSharing", // 屏幕共享
    ]

    /// 当前生效的名单：关闭时为空
    var passthroughApps: Set<String> {
        enabled ? Set(bundleIDs) : []
    }
}

/// 远程桌面模式：远程桌面 App 在前台时，按键原样交给它转发给远程电脑（ADR-0027）。
@MainActor
@Observable
public final class RemoteDesktopMode {
    public private(set) var settings: RemoteDesktopSettings
    /// 远程桌面 App 正在前台，MAIO 的快捷键已让出
    public private(set) var isActive = false

    @ObservationIgnored private let config: ConfigStore
    @ObservationIgnored private let input: InputEngine
    @ObservationIgnored private var frontmost: String?
    @ObservationIgnored private let logger = Logger(subsystem: "app.maio", category: "input")

    init(config: ConfigStore, input: InputEngine) {
        self.config = config
        self.input = input
        settings = config.load(RemoteDesktopSettings.self, from: RemoteDesktopSettings.path, default: RemoteDesktopSettings())
        input.updatePassthroughApps(settings.passthroughApps)
    }

    public func setEnabled(_ enabled: Bool) {
        update { $0.enabled = enabled }
    }

    public func add(_ bundleID: String) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !settings.bundleIDs.contains(trimmed) else { return }
        update { $0.bundleIDs.append(trimmed) }
    }

    public func remove(_ bundleID: String) {
        update { $0.bundleIDs.removeAll { $0 == bundleID } }
    }

    public func restoreDefaults() {
        update { $0.bundleIDs = RemoteDesktopSettings.defaultBundleIDs }
    }

    func updateFrontmost(_ bundleID: String?) {
        frontmost = bundleID
        refreshActive()
    }

    private func update(_ change: (inout RemoteDesktopSettings) -> Void) {
        change(&settings)
        config.save(settings, to: RemoteDesktopSettings.path)
        input.updatePassthroughApps(settings.passthroughApps)
        refreshActive()
    }

    private func refreshActive() {
        let active = frontmost.map(settings.passthroughApps.contains) ?? false
        guard active != isActive else { return }
        isActive = active
        logger.info("远程桌面模式\(active ? "开始" : "结束", privacy: .public)：\(self.frontmost ?? "-", privacy: .public)")
    }
}
