import AppKit
import MAIOCore
import MAIOKit
import os

/// 自动更新（ADR-0016）：定期检查 GitHub Releases → 自动下载并校验 → 询问用户 → 替换并重启。
/// 用户选择：自动下载，确认后才安装；自动检查默认开启。
@MainActor
@Observable
final class Updater {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case downloading(String)
        case ready(UpdateInstaller.Prepared)
        case installing
        case failed(String)
    }

    private(set) var state: State = .idle
    var settings: UpdateSettings {
        didSet { config.save(settings, to: UpdateSettings.path) }
    }

    let currentVersion: AppVersion?
    /// 新版本下载好时调用（显示询问窗口）
    @ObservationIgnored var onReady: ((UpdateInstaller.Prepared) -> Void)?

    @ObservationIgnored private let config: ConfigStore
    @ObservationIgnored private let overlay: any OverlayService
    @ObservationIgnored private let feedURL: URL
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "app.maio", category: "update")

    static let defaultFeed = URL(string: "https://api.github.com/repos/sanhua1/MAIO/releases/latest")

    init(config: ConfigStore, overlay: any OverlayService) {
        self.config = config
        self.overlay = overlay
        settings = config.load(UpdateSettings.self, from: UpdateSettings.path, default: UpdateSettings())
        currentVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            .flatMap(AppVersion.init)
        // 调试用：MAIO_UPDATE_FEED 指向本地的 JSON（file://）
        let override = ProcessInfo.processInfo.environment["MAIO_UPDATE_FEED"].flatMap(URL.init(string:))
        feedURL = override ?? Self.defaultFeed ?? URL(filePath: "/dev/null")
    }

    /// 开发版（Debug）用开发证书签名，和发布版签名不同，装不了发布版，所以不自动检查
    private var automaticChecksSupported: Bool {
        #if DEBUG
            ProcessInfo.processInfo.environment["MAIO_UPDATE_FEED"] != nil
        #else
            true
        #endif
    }

    func start() {
        reportPreviousInstall()
        guard automaticChecksSupported else { return }
        timer = Task { [weak self] in
            // 启动后等一会儿再检查，不和功能启动抢资源
            try? await Task.sleep(for: .seconds(30))
            while !Task.isCancelled {
                await self?.checkIfDue()
                try? await Task.sleep(for: .seconds(60 * 60))
            }
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func checkIfDue() async {
        guard settings.isCheckDue(now: Date()), !isBusy else { return }
        await check(userInitiated: false)
    }

    private var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing, .ready: true
        default: false
        }
    }

    /// userInitiated：用户点了"检查更新"——结果都提示，并且忽略"跳过这个版本"
    func check(userInitiated: Bool) async {
        if case let .ready(prepared) = state {
            onReady?(prepared)
            return
        }
        guard !isBusy else { return }
        state = .checking
        do {
            let release = try await fetchLatest()
            settings.lastCheck = Date()
            guard let currentVersion, release.version > currentVersion else {
                state = .upToDate
                if userInitiated {
                    overlay.showHUD("MAIO 已是最新版本（\(currentVersion?.description ?? "开发版")）", symbol: "checkmark.circle")
                }
                return
            }
            if !userInitiated, settings.skippedVersion == release.version.description {
                state = .idle
                return
            }
            try await download(release)
        } catch {
            fail(error, userInitiated: userInitiated)
        }
    }

    private func fetchLatest() async throws -> ReleaseInfo {
        var request = URLRequest(url: feedURL, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MAIO-Updater", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "检查更新失败（HTTP \(http.statusCode)）"])
        }
        return try ReleaseInfo.parse(data)
    }

    private func download(_ release: ReleaseInfo) async throws {
        state = .downloading(release.version.description)
        let directory = URL.cachesDirectory.appending(
            path: "app.maio.MAIO/Updates/\(release.version)",
            directoryHint: .isDirectory,
        )
        let prepared = try await UpdateInstaller.prepare(
            release, workDirectory: directory, requirement: nil, bundleID: Bundle.main.bundleIdentifier ?? "app.maio.MAIO",
        )
        state = .ready(prepared)
        onReady?(prepared)
    }

    /// 替换并重启：先启动替换脚本，再退出 MAIO（脚本等 MAIO 退出后才动文件）
    func install(_ prepared: UpdateInstaller.Prepared) {
        let destination = Bundle.main.bundleURL
        do {
            try UpdateInstaller.checkReplaceable(destination)
            try FileManager.default.createDirectory(at: resultFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try UpdateInstaller.launchReplacement(new: prepared.appURL, installedAt: destination, resultFile: resultFile)
            settings.skippedVersion = nil
            state = .installing
            NSApp.terminate(nil)
        } catch {
            fail(error, userInitiated: true)
        }
    }

    func skip(_ prepared: UpdateInstaller.Prepared) {
        settings.skippedVersion = prepared.release.version.description
        state = .idle
    }

    private func fail(_ error: any Error, userInitiated: Bool) {
        let message = error.localizedDescription
        logger.error("更新失败：\(message, privacy: .public)")
        state = .failed(message)
        if userInitiated {
            overlay.showError(message)
        }
    }

    // MARK: 上一次安装的结果

    private var resultFile: URL {
        config.url(for: "data/update-result.txt")
    }

    /// 替换脚本把结果写在文件里；新版本启动时读出来提示一次
    private func reportPreviousInstall() {
        guard let text = try? String(contentsOf: resultFile, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: resultFile)
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result == "ok" {
            overlay.showHUD("MAIO 已更新到 \(currentVersion?.description ?? "新版本")", symbol: "checkmark.seal")
        } else {
            overlay.showError("更新没有完成：\(result)。可以到 GitHub Releases 手动下载安装")
        }
    }
}
