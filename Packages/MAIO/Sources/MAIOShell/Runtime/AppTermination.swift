import AppKit

/// 退出 MAIO 一律走这里。
///
/// `applicationShouldTerminate` 返回 `.terminateLater`，在主线程上异步清理功能。如果 `terminate` 是在主队列的回调里
/// （`Task { @MainActor }`、`DispatchQueue.main`、信号源）调用的，AppKit 会在这个回调里开一个等待循环；主队列是串行的，
/// 清理任务排在后面永远执行不到，进程就卡住了。放到 run loop 的 block 里调用就没有这个问题。
@MainActor
public enum AppTermination {
    public static func request() {
        RunLoop.main.perform { NSApp.terminate(nil) }
    }
}
