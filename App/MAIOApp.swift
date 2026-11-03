import AppKit
import MAIOShell

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

    func applicationDidFinishLaunching(_: Notification) {
        Task { await controller.start() }
    }

    func application(_: NSApplication, open urls: [URL]) {
        urls.forEach(controller.handle(url:))
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        controller.showSettings()
        return false
    }

    func applicationWillTerminate(_: Notification) {
        // 同步等待功能清理（释放 event tap、终止子进程），最多 1 秒
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached { [controller] in
            await controller.stop()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 1)
    }
}
