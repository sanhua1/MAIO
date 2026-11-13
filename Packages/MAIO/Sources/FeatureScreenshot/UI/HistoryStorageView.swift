import SwiftUI

/// 截图历史的占用和手动清理：删除最旧的 N MB、删除某日期之前的、清空（收藏的不删）。
struct HistoryStorageView: View {
    enum Cleanup: Identifiable {
        case oldest(Int)
        case before(Date)
        case all

        var id: String {
            switch self {
            case let .oldest(size): "oldest-\(size)"
            case let .before(date): "before-\(date.timeIntervalSince1970)"
            case .all: "all"
            }
        }

        var title: String {
            switch self {
            case let .oldest(size): "删除最旧的 \(size) MB 截图？"
            case let .before(date): "删除 \(date.formatted(date: .long, time: .omitted)) 之前的截图？"
            case .all: "清空全部截图历史？"
            }
        }
    }

    let store: ScreenshotHistoryStore
    @State private var stats: ScreenshotHistoryStore.Stats?
    @State private var megabytes = 200
    @State private var cutoff = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
    @State private var pending: Cleanup?
    @State private var message: String?

    var body: some View {
        Group {
            LabeledContent("当前占用") {
                if let stats {
                    Text(summary(stats)).monospacedDigit()
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            LabeledContent("删除最旧的") {
                // 分组表单里的 TextField 默认没有边框、基线也不和旁边的文字对齐，要显式指定
                HStack(alignment: .firstTextBaseline) {
                    TextField("", value: $megabytes, format: .number)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Text("MB").foregroundStyle(.secondary)
                    Button("删除…") { pending = .oldest(max(1, megabytes)) }
                }
            }
            LabeledContent("删除此日期之前的") {
                HStack {
                    DatePicker("", selection: $cutoff, displayedComponents: .date).labelsHidden()
                    Button("删除…") { pending = .before(cutoff) }
                }
            }
            LabeledContent("清空") {
                Button("清空截图历史…", role: .destructive) { pending = .all }
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .task { await refresh() }
        .confirmationDialog(pending?.title ?? "", isPresented: isConfirming, presenting: pending) { cleanup in
            Button("删除", role: .destructive) { Task { await perform(cleanup) } }
        } message: { _ in
            Text("收藏的截图不会被删除。此操作无法撤销。")
        }
    }

    private func summary(_ stats: ScreenshotHistoryStore.Stats) -> String {
        let size = ByteCountFormatter.string(fromByteCount: stats.bytes, countStyle: .decimal)
        let pinned = stats.pinnedCount > 0 ? "（收藏 \(stats.pinnedCount) 张）" : ""
        return "\(size) · \(stats.count) 张\(pinned)"
    }

    private var isConfirming: SwiftUI.Binding<Bool> {
        SwiftUI.Binding(get: { pending != nil }, set: {
            if !$0 {
                pending = nil
            }
        })
    }

    private func perform(_ cleanup: Cleanup) async {
        let records = await store.records
        let ids = switch cleanup {
        case let .oldest(size): HistoryRetention.oldest(records, bytes: Int64(size) * 1_000_000)
        case let .before(date): HistoryRetention.before(records, date: date)
        case .all: records.filter { !$0.pinned }.map(\.id)
        }
        do {
            try await store.delete(ids)
            message = "已删除 \(ids.count) 张"
        } catch {
            message = error.localizedDescription
        }
        pending = nil
        await refresh()
    }

    private func refresh() async {
        stats = await store.stats
    }
}
