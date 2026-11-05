import AppKit

/// 执行启动器自带的系统操作。
@MainActor
enum SystemActionRunner {
    enum Failure: LocalizedError {
        case failed(String)
        /// 没有允许 MAIO 控制某个 App（系统设置 › 隐私与安全性 › 自动化）
        case notAuthorized(String)

        var errorDescription: String? {
            switch self {
            case let .failed(message): message
            case let .notAuthorized(app): "需要允许 MAIO 控制“\(app)”：系统设置 › 隐私与安全性 › 自动化"
            }
        }
    }

    static func run(_ action: SystemAction) async throws {
        switch action {
        case .lockScreen: try lockScreen()
        case .sleep: try await shell("/usr/bin/pmset", ["sleepnow"])
        case .displaySleep: try await shell("/usr/bin/pmset", ["displaysleepnow"])
        case .screenSaver:
            let engine = URL(filePath: "/System/Library/CoreServices/ScreenSaverEngine.app")
            _ = try await NSWorkspace.shared.openApplication(at: engine, configuration: NSWorkspace.OpenConfiguration())
        // 发给 loginwindow 的"显示确认框"事件：系统自己弹出 退出登录 / 重新启动 / 关机 的确认框
        case .logOut: try await appleScript("tell application \"loginwindow\" to «event aevtlogo»", app: "loginwindow")
        case .restart: try await appleScript("tell application \"loginwindow\" to «event aevtrrst»", app: "loginwindow")
        case .shutDown: try await appleScript("tell application \"loginwindow\" to «event aevtrsdn»", app: "loginwindow")
        case .emptyTrash:
            guard confirmEmptyTrash() else { return }
            try await appleScript("tell application \"Finder\" to empty trash", app: "Finder")
        case .toggleDarkMode:
            try await appleScript(
                "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode",
                app: "System Events",
            )
        }
    }

    /// 立即锁屏：和菜单栏"锁定屏幕"同一个函数（login.framework 的 SACLockScreenImmediate，私有，运行时查找）
    private static func lockScreen() throws {
        typealias LockFunction = @convention(c) () -> Int32
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
              let symbol = dlsym(handle, "SACLockScreenImmediate")
        else { throw Failure.failed("这个系统版本不支持直接锁屏，请用 ⌃⌘Q") }
        let lock = unsafeBitCast(symbol, to: LockFunction.self)
        _ = lock()
    }

    private static func confirmEmptyTrash() -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "清空废纸篓？"
        alert.informativeText = "废纸篓里的项目会被永久删除，不能撤销。"
        alert.addButton(withTitle: "清空废纸篓")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func shell(_ executable: String, _ arguments: [String]) async throws {
        let status = try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(filePath: executable)
            process.arguments = arguments
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }.value
        guard status == 0 else { throw Failure.failed("\(executable) 退出码 \(status)") }
    }

    private static func appleScript(_ source: String, app: String) async throws {
        let failure: Failure? = await Task.detached(priority: .userInitiated) {
            guard let script = NSAppleScript(source: source) else { return Failure.failed("脚本无效") }
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            guard let error else { return nil }
            let number = error[NSAppleScript.errorNumber] as? Int
            if number == -1743 {
                return Failure.notAuthorized(app)
            }
            // -128：用户在确认框里点了取消
            if number == -128 {
                return nil
            }
            return Failure.failed(error[NSAppleScript.errorMessage] as? String ?? "错误 \(number ?? 0)")
        }.value
        if let failure {
            throw failure
        }
    }
}
