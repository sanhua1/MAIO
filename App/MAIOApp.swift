import AppKit
import MAIOShell
import os

/// 程序入口：菜单栏常驻 App（无 Dock 图标）。所有组装逻辑在 MAIOAppController 中。
@main
enum MAIOMain {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            withExtendedLifetime(delegate) { app.run() }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = MAIOAppController(catalog: FeatureCatalog.all)
    private var termSource: (any DispatchSourceSignal)?

    func applicationDidFinishLaunching(_: Notification) {
        handleTerminationSignal()
        Task { await controller.start() }
    }

    /// `pkill` / `make run` 发的是 SIGTERM，默认直接结束进程，功能来不及清理（按 App 改键会把对调留在键盘上）。
    /// 改为走正常退出流程。
    private func handleTerminationSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { AppTermination.request() }
        source.resume()
        termSource = source
    }

    func application(_: NSApplication, open urls: [URL]) {
        urls.forEach(controller.handle(url:))
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        controller.showSettings()
        return false
    }

    /// 退出前先清理功能（释放 event tap、终止子进程、把按 App 改键写回键盘），最多等 2 秒。
    /// 清理要在主线程上跑，不能在 applicationWillTerminate 里同步等（主线程卡住，等到超时也没清理）。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let logger = Logger(subsystem: "app.maio", category: "host")
        var replied = false
        let reply = { (result: String) in
            guard !replied else { return }
            replied = true
            logger.info("退出：功能清理\(result, privacy: .public)")
            sender.reply(toApplicationShouldTerminate: true)
        }
        Task {
            await controller.stop()
            reply("完成")
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            reply("超时")
        }
        return .terminateLater
    }
}
