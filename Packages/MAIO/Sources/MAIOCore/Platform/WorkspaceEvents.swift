import AppKit
import MAIOKit
import os

/// 系统事实：前台 App 变化等。
///
/// 只靠 `didActivateApplicationNotification` 不够：英雄联盟这类由启动器拉起、直接进全屏的游戏，
/// 启动那一刻要么收不到通知，要么通知里还拿不到 bundle ID，前台就一直停在旧值上，直到用户切出去再切回来。
/// 所以在 App 激活或启动后，过一会儿再读一次 `NSWorkspace.frontmostApplication` 校正。
@MainActor
public final class WorkspaceEvents: SystemEventService {
    public private(set) var frontmostBundleID: String?
    private var continuations: [UUID: AsyncStream<String?>.Continuation] = [:]
    private var handlers: [(String?) -> Void] = []
    private var observers: [any NSObjectProtocol] = []
    private var recheckTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "app.maio", category: "workspace")
    /// 激活 / 启动之后再校正前台的时间点
    private static let recheckDelays: [Duration] = [.milliseconds(500), .seconds(2), .seconds(5)]

    public init() {
        frontmostBundleID = Self.bundleID(of: NSWorkspace.shared.frontmostApplication)
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main,
        ) { [weak self] note in
            let bundleID = Self.bundleID(of: note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
            MainActor.assumeIsolated {
                self?.update(bundleID, source: "激活")
                self?.scheduleRecheck()
            }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRecheck() }
        })
    }

    func onFrontmostChange(_ handler: @escaping (String?) -> Void) {
        handlers.append(handler)
        handler(frontmostBundleID)
    }

    public func frontmostApplicationChanges() -> AsyncStream<String?> {
        let (stream, continuation) = AsyncStream.makeStream(of: String?.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.continuations[id] = nil }
        }
        return stream
    }

    /// bundle ID 还没登记好时从 App 路径读 Info.plist
    nonisolated static func bundleID(of app: NSRunningApplication?) -> String? {
        guard let app else { return nil }
        if let id = app.bundleIdentifier {
            return id
        }
        return app.bundleURL.flatMap { Bundle(url: $0)?.bundleIdentifier }
    }

    private func scheduleRecheck() {
        recheckTask?.cancel()
        recheckTask = Task { [weak self] in
            for delay in Self.recheckDelays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                // 读不到就不动，免得把正确的值冲掉
                if let bundleID = Self.bundleID(of: NSWorkspace.shared.frontmostApplication) {
                    self?.update(bundleID, source: "校正")
                }
            }
        }
    }

    private func update(_ bundleID: String?, source: String) {
        guard bundleID != frontmostBundleID else { return }
        logger.info("前台 App（\(source, privacy: .public)）：\(bundleID ?? "nil", privacy: .public)")
        frontmostBundleID = bundleID
        handlers.forEach { $0(bundleID) }
        continuations.values.forEach { $0.yield(bundleID) }
    }
}
