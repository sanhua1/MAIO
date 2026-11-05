import MAIOKit
import Synchronization

/// 键盘 tap 线程上的 Finder 改键过滤器（ADR-0017）。决策在 `FinderKeymap`，这里只持有快照。
/// "正在输入文字"、"剪切待粘贴"由主线程写入。
final class FinderKeyFilter: RealtimeKeyFilter {
    private struct Snapshot {
        var config: FinderKeyConfig
        var state = FinderKeyState()
    }

    private let snapshot: Mutex<Snapshot>
    private let continuation: AsyncStream<FinderAction>.Continuation
    /// 需要主线程处理的动作（剪切、新建文件、打开终端）
    let actions: AsyncStream<FinderAction>

    init(config: FinderKeyConfig) {
        snapshot = Mutex(Snapshot(config: config))
        (actions, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(8))
    }

    func update(_ config: FinderKeyConfig) {
        snapshot.withLock { $0.config = config }
    }

    func setEditing(_ editing: Bool) {
        snapshot.withLock { $0.state.isEditing = editing }
    }

    func setCutPending(_ pending: Bool) {
        snapshot.withLock { $0.state.cutPending = pending }
    }

    var isCutPending: Bool {
        snapshot.withLock { $0.state.cutPending }
    }

    func finish() {
        continuation.finish()
    }

    func process(_ event: KeyEvent, _ environment: RealtimeEnvironment) -> KeyFilterDecision {
        let result = snapshot.withLock { value in
            FinderKeymap.decide(event, frontmost: environment.frontmostBundleID, config: value.config, state: &value.state)
        }
        if let action = result.action {
            continuation.yield(action)
        }
        return result.decision
    }
}
