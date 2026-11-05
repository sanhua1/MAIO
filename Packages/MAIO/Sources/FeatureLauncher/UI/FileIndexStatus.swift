import Observation

/// 文件索引的状态，功能和设置页共用（设置页显示条数、进度，提供"重建索引"）
@MainActor
@Observable
final class FileIndexStatus {
    var state: FileIndexState = .idle
    var fullDiskAccess = false
    var rebuild: (() -> Void)?

    var summary: String {
        switch state {
        case .idle: "未启用"
        case .loading: "正在读取索引…"
        case let .scanning(found): "正在建立索引：已找到 \(found.formatted()) 个"
        case let .ready(count, scannedAt):
            "已索引 \(count.formatted()) 个文件和文件夹" +
                (scannedAt.map { "，上次完整扫描 \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")
        case let .failed(message): message
        }
    }
}
