import AppKit
import MAIOKit

/// 系统事实：前台 App 变化等。
@MainActor
public final class WorkspaceEvents: SystemEventService {
    public private(set) var frontmostBundleID: String?
    private var continuations: [UUID: AsyncStream<String?>.Continuation] = [:]
    private var handlers: [(String?) -> Void] = []
    private var observer: (any NSObjectProtocol)?

    public init() {
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main,
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            MainActor.assumeIsolated { self?.update(bundleID) }
        }
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

    private func update(_ bundleID: String?) {
        guard bundleID != frontmostBundleID else { return }
        frontmostBundleID = bundleID
        handlers.forEach { $0(bundleID) }
        continuations.values.forEach { $0.yield(bundleID) }
    }
}
